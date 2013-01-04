use strict;
use warnings;
use Test::More tests => 5;
use Test::Mojo;
use AnyEvent::Ident qw( ident_server );
use Mojolicious::Lite;

plugin 'ident' => { 
  port => do {
    my $server = ident_server '127.0.0.1', 0, sub {
      my $tx = shift;
      $tx->reply_with_user('AwesomeOS', 'foo');
    };
    $server->bindport;
  }
};

get '/' => sub { shift->render_text('index') };

get '/ident' => sub {
  my($self) = @_;
  my $ident = $self->ident;
  $self->render_json({ username => $ident->username, os => $ident->os, remote_address => $ident->remote_address });
};

my $t = Test::Mojo->new;

$t->get_ok("/ident")
  ->status_is(200)
  ->json_is('/username',       'foo')
  ->json_is('/os',             'AwesomeOS')
  ->json_is('/remote_address', '127.0.0.1');

