# Mojolicious::Plugin::Ident [![Build Status](https://secure.travis-ci.org/plicease/Mojolicious-Plugin-Ident.png)](http://travis-ci.org/plicease/Mojolicious-Plugin-Ident)

Mojolicious plugin to interact with a remote ident service

# SYNOPSIS

    use Mojolicious::Lite;
    plugin 'ident';
    
    # log the ident user for every connection (async ident)
    under sub {
      shift->ident(sub {
        my $id_res = shift; # $id_res isa Mojolicious::Plugin::Ident::Response
        if($id_res->is_success) {
          app->log->info("ident user is " . $id_res->username);
        } else {
          app->log->info("unable to ident remote user");
        }
      });

      1;
    };
    
    # get the username of the remote using ident protocol
    get '/' => sub {
      my $self = shift;
      my $id_res = $self->ident; # $id_res isa Mojolicious::Plugin::Ident::Response
      $self->render(text => "hello " . $id_res->username);
    };
    
    # only allow access to the user on localhost which
    # started the mojolicious lite app with non-blocking
    # ident call (requires Mojolicious 4.28)
    under sub {
      my($self) = @_;
      $self->ident_same_user(sub {
        my($same) = @_;
        unless($same) {
          return $self->render(
            text   => 'permission denied',
            status => 403,
          );
        }
        $self->continue;
      });
      return undef;
    };
    
    get '/private' => sub {
      shift->render(text => "secret place");
    };
    
    # only allow access to the user on localhost which 
    # started the mojolicious lite app (all versions of
    # Mojolicious)
    under sub {
      my($self) = @_;
      if($self->ident_same_user) {
        return 1;
      } else {
        $self->render(
          text   => 'permission denied',
          status => 403,
        );
      }
    };
    
    get '/private' => sub {
      shift->render(text => "secret place");
    };

# DESCRIPTION

This plugin provides an interface for querying an ident service on a 
remote system.  The ident protocol helps identify the user of a 
particular TCP connection.  If the remote client connecting to your 
Mojolicious application is running the ident service you can identify 
the remote users' name.  This can be useful for determining the source 
of abusive or malicious behavior.  Although ident can be used to 
authenticate users, it is not recommended for untrusted networks and 
systems (see CAVEATS below).

Under the covers this plugin uses [AnyEvent::Ident](http://search.cpan.org/perldoc?AnyEvent::Ident).

# OPTIONS

## timeout

    plugin 'ident' => { timeout => 60 };

Default number of seconds to wait before timing out when contacting the remote
ident server.  The default is 2.

## port

    plugin 'ident' => { port => 113 };

Port number to connect to.  Usually this will be 113, but you may want to change
this for testing or some other purpose.

# HELPERS

## ident \[ $tx, \[ $timeout \] \], \[ $callback \]

This helper makes a ident request.  This helper takes two optional arguments,
a transaction `$tx` and a timeout `$timeout`.  If not specified, the current
transaction and the configured default timeout will be used.  If a callback
is provided then the request is non-blocking.  If no callback is provided,
it will block until a response comes back or the timeout expires.

With a callback (non-blocking):

    get '/' => sub {
      my $self = shift;
      $self->ident(sub {
        my $res = shift->res;
        if($res->is_success)
        {
          $self->render(text =>
            "username: " . $res->username .
            "os:       " . $res->os
          );
        }
        else
        {
          $self->render(text =>
            "error: " . $res->error_type
          );
        }
      };
    };

The callback is passed an instance of [Mojolicious::Plugin::Ident::Response](http://search.cpan.org/perldoc?Mojolicious::Plugin::Ident::Response).  Even if
the response is an error.  The `is_success` method on [Mojolicious::Plugin::Ident::Response](http://search.cpan.org/perldoc?Mojolicious::Plugin::Ident::Response)
will tell you if the response is an error or not.

Without a callback (blocking):

    get '/' => sub {
      my $self = shift;
      my $ident = $self->ident;
      $self->render(text =>
        "username: " . $ident->username .
        "os:       " . $ident->os
      );
    };

Returns an instance of [Mojolicious::Plugin::Ident::Response](http://search.cpan.org/perldoc?Mojolicious::Plugin::Ident::Response), which 
provides two fields, username and os for the remote connection.

When called in blocking mode (without a callback), the ident helper will throw 
an exception if

- it cannot connect to the remote's ident server
- the connection to the remote's ident server times out
- the remote ident server returns an error

    under sub { eval { shift->ident->same_user } };
    get '/private' => 'private_route';

The ident response class also has a same\_user method which can be used
to determine if the user which started the Mojolicious application and
the remote user are the same.  The user is considered the same if the
remote connection came over the loopback address (127.0.0.1) and the
username matches either the server's username or real UID.  Although
this can be used as a simple authentication method, keep in mind that it
may not be secure (see CAVEATS below).

## ident\_same\_user \[ $tx, \[ $timeout \] \], \[ $callback \]

This helper makes an ident request and attempts to determine if the 
user that made the request is the same as the one that started the
Mojolicious application.  This helper takes two optional arguments,
a transaction `$tx` and a timeout `$timeout`.  If not specified, the current
transaction and the configured default timeout will be used.  If a callback
is provided then the request is non-blocking.  If no callback is provided,
it will block until a response comes back or the timeout expires.

With a callback (non-blocking):

    get '/private' => sub {
      my $self = shift;
      $self->ident_same_user(sub {
        my $same_user = shift;
        $same_user ? $self->render(text => 'private text') : $self->render_not_found;
      });
    }

When the response comes back it will call the callback and pass in a boolean
value indicating if the user is the same.  If the ident request connects
and does not timeout, then result will be cached.  If cached the callback may
be called immediately, before re-entering the event loop.

Without a callback (blocking):

    under sub { shift->ident_same_user };
    get '/private' => 'private_route';

without a callback this helper will return true or false depending on
if the user is the same.  It should never throw an exception.

# CAVEATS

[The RFC for the ident protocol](http://tools.ietf.org/html/rfc1413)
clearly states that ident should not be used for authentication, at
most it should be used only for audit (for example annotating log
files).

In Windows and possibly other operating systems, an unprivileged user
can listen to port 113 and on any untrusted network, a remote ident
server is not a secure authentication mechanism.  Most modern operating
systems do not enable the ident service by default, so unless you have
control both the client and the server and can configure the ident
service securely on both, its usefulness is reduced.

Using this module in the non-blocking mode requires that [AnyEvent](http://search.cpan.org/perldoc?AnyEvent) use 
its [EV](http://search.cpan.org/perldoc?EV) implementation, which is also used by [Mojolicious](http://search.cpan.org/perldoc?Mojolicious), if it is 
loaded.  This shouldn't be a problem, as [EV](http://search.cpan.org/perldoc?EV) is a prerequisite to this 
module (though it does not use it directly), and both [AnyEvent](http://search.cpan.org/perldoc?AnyEvent) and 
[Mojolicious](http://search.cpan.org/perldoc?Mojolicious) will prefer to use [EV](http://search.cpan.org/perldoc?EV) if it is installed.  You do have 
to make sure that you do not force another event loop, such as 
[AnyEvent::Loop](http://search.cpan.org/perldoc?AnyEvent::Loop), unless you are using only the blocking mode.

[Mojolicious](http://search.cpan.org/perldoc?Mojolicious) 4.28 introduced support for non-blocking operations in bridges.
Prior to that if a bridge returned false the server would generate a
404 "Not Found" reply.  In 4.29 a bridge returning false would not render
anything and thus timeout if the bridge didn't render anything.  Thus in
older versions of [Mojolicious](http://search.cpan.org/perldoc?Mojolicious) this:

    under sub { shift->ident_same_user };

would return 404 if the remote and local users are not the same.  To get the
same behavior in both new and old versions of [Mojolicious](http://search.cpan.org/perldoc?Mojolicious):

    under sub {
      my($self) = @_;
      if($self->ident_same_user) {
        return 0;
      } else {
        $self->render_not_found;
        return 1;
      }
    };

Most of the time you should really return a 403, instead of not found (as in
the synopsis above), but this is what you would want to do if you wanted a
resource to be invisible and unavailable rather than just unavailable to the
wrong user.

I only mention this because old versions of this plugin had documentation
which included the older form in its synopsis.

# AUTHOR

Graham Ollis <plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
