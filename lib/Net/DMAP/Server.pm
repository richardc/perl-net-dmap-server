package Net::DMAP::Server;
use strict;
use warnings;
use POE::Component::Server::HTTP;
use Net::Rendezvous::Publish;
use Net::DAAP::DMAP qw( dmap_pack );
use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw( debug path tracks port httpd uri publisher service ));

our $VERSION = '0.01';

=head1 NAME

Net::DMAP::Server - base class for D[A-Z]AP servers

=head1 SYNOPSIS

  package Net::DZAP::Server;
  use base qw( Net::DMAP::Server );
  sub protocol { 'dzap' }

  1;

  =head1 NAME

  Net::DZAP::Server - Digital Zebra Access Protocol (iZoo) Server

  =cut


=head1 DESCRIPTION

Net::DMAP::Server is a base class for implementing DMAP servers.  It's
probably not hugely useful to you directly, and you're better off
looking at Net::DPAP::Server or Net::DAAP::Server.

=cut


sub new {
    my $class = shift;
    my $self = $class->SUPER::new( { tracks => {}, @_ } );
    $self->find_tracks;
    #print Dump $self;
    $self->httpd( POE::Component::Server::HTTP->new(
        Port => $self->port,
        ContentHandler => { '/' => sub { $self->handler(@_) } },
       ) );

    my $publisher = Net::Rendezvous::Publish->new
      or die "couldn't make a Responder object";
    $self->publisher( $publisher );
    $self->service( $publisher->publish(
        name => ref $self,
        type => '_'.$self->protocol.'._tcp',
        port => $self->port,
       ) );

    return $self;
}

sub handler {
    my $self = shift;
    my ($request, $response) = @_;

    local $self->{uri};
    $self->uri( $request->uri );
    print $request->uri, "\n" if $self->debug;

    my %params = map { split /=/, $_, 2 } split /&/, $self->uri->query;
    my (undef, $method, @args) = split m{/}, $request->uri->path;
    $method =~ s/-/_/g; # server-info => server_info

    if ($self->can( $method )) {
        my $res = $self->$method( @args );
        #print Dump $res;
        $response->code( $res->code );
        $response->content( $res->content );
        $response->content_type( $res->content_type );
        return $response->code;
    }

    print "Can't $method: ". $self->uri;
    $response->code( 500 );
    return 500;
}

sub _dmap_response {
    my $self = shift;
    my $dmap = shift;
    my $response = HTTP::Response->new( 200 );
    $response->content_type( 'application/x-dmap-tagged' );
    $response->content( dmap_pack $dmap );
    #print Dump $dmap if $self->debug && $self->uri =~/type=photo/;
    return $response;
}


sub content_codes {
    my $self = shift;
    $self->_dmap_response( [[ 'dmap.contentcodesresponse' => [
        [ 'dmap.status'             => 200 ],
        map { [ 'dmap.dictionary' => [
            [ 'dmap.contentcodesnumber' => $_->{ID}   ],
            [ 'dmap.contentcodesname'   => $_->{NAME} ],
            [ 'dmap.contentcodestype'   => $_->{TYPE} ],
           ] ] } values %$Net::DAAP::DMAP::Types,
       ]]] );
}

sub login {
    my $self = shift;
    $self->_dmap_response( [[ 'dmap.loginresponse' => [
        [ 'dmap.status'    => 200 ],
        [ 'dmap.sessionid' =>  42 ],
       ]]] );
}

sub logout { HTTP::Response->new( 200 ) }

sub update {
    my $self = shift;
    return HTTP::Response->new( RC_WAIT )
      if $self->uri =~ m{revision-number=42};

    $self->_dmap_response( [[ 'dmap.updateresponse' => [
        [ 'dmap.status'         => 200 ],
        [ 'dmap.serverrevision' =>  42 ],
       ]]] );
}



=head1 BUGS

The Digital Zebra Access Protocol does not exist, so you'll have to
manually acquire your own horses and paint them.


=head1 AUTHOR

Richard Clamp <richardc@unixbeard.net>

=head1 COPYRIGHT

Copyright 2004 Richard Clamp.  All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

Net::DAAP::Server, Net::DPAP::Server

=cut

1;
