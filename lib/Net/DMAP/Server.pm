package Net::DMAP::Server;
use strict;
use warnings;
use POE::Component::Server::HTTP;
use Net::Rendezvous::Publish;
use Net::DAAP::DMAP qw( dmap_pack );
use Sys::Hostname;
use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw( debug port name path tracks ),
                          qw( httpd uri ),
                          # Rendezvous::Publish stuff
                          qw( publisher service ));
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

use YAML;

sub new {
    my $class = shift;
    my $self = $class->SUPER::new( { tracks => {}, @_ } );
    $self->name( ref($self) ." " . hostname . " $$" ) unless $self->name;
    $self->find_tracks;
    #print Dump $self;
    $self->httpd( POE::Component::Server::HTTP->new(
        Port => $self->port,
        ContentHandler => { '/' => sub { $self->_handler(@_) } },
       ) );

    my $publisher = Net::Rendezvous::Publish->new
      or die "couldn't make a Responder object";
    $self->publisher( $publisher );
    $self->service( $publisher->publish(
        name => $self->name,
        type => '_'.$self->protocol.'._tcp',
        port => $self->port,
       ) );

    return $self;
}

sub _handler {
    my $self = shift;
    my ($request, $response) = @_;
    # always the same
    $response->code( RC_OK );
    $response->content_type( 'application/x-dmap-tagged' );

    local $self->{uri};
    $self->uri( $request->uri );
    print $request->uri, "\n" if $self->debug;

    my $path = $self->uri->path;
    $path =~ s{^/}{};
    if ($path =~ m{^databases/\d+/items/(\d+)\.}) {
        $response->content( $self->tracks->{$1}->data );
        return RC_OK;
    }
    if ($path =~ m{^databases/(\d+)/items}) {
        $response->content( $self->database_items( $1 ) );
        return RC_OK;
    }
    if ($path =~ m{^databases/(\d+)/containers/(\d+)}) {
        $response->content( $self->playlist_items( $1, $2 ) );
        return RC_OK;
    }
    if ($path =~ m{^databases/(\d+)/containers}) {
        $response->content( $self->database_playlists( $1 ) );
        return RC_OK;
    }
    $path =~ s/-/_/g;

    if ($self->can( $path )) {
        $self->$path( $response );
        return $response->code;
    }

    print "Can't handle '$path'\n" if $self->debug;
    $response->code( 500 );
    return 500;
}


sub _dmap_pack {
    my $self = shift;
    my $dmap = shift;
    return dmap_pack $dmap;
}


sub content_codes {
    my $self = shift;
    my $response = shift;
    $response->content($self->_dmap_pack(
        [[ 'dmap.contentcodesresponse' => [
            [ 'dmap.status'             => 200 ],
            map { [ 'dmap.dictionary' => [
                [ 'dmap.contentcodesnumber' => $_->{ID}   ],
                [ 'dmap.contentcodesname'   => $_->{NAME} ],
                [ 'dmap.contentcodestype'   => $_->{TYPE} ],
               ] ] } values %$Net::DAAP::DMAP::Types,
           ]]] ));
}

sub login {
    my $self = shift;
    my $response = shift;
    $response->content( $self->_dmap_pack(
        [[ 'dmap.loginresponse' => [
            [ 'dmap.status'    => 200 ],
            [ 'dmap.sessionid' =>  42 ],
           ]]] ));
}

sub logout { }

sub update {
    my $self = shift;
    my $response = shift;
    # XXX queue these responses to come back later?
    if ($self->uri =~ m{revision-number=42}) {
        $response->code( RC_WAIT );
        return;
    }

    $response->content( $self->_dmap_pack(
        [[ 'dmap.updateresponse' => [
            [ 'dmap.status'         => 200 ],
            [ 'dmap.serverrevision' =>  42 ],
           ]]] ));
}

sub databases {
    my $self = shift;
    my $response = shift;
    $response->content( $self->_dmap_pack(
        [[ 'daap.serverdatabases' => [
            [ 'dmap.status' => 200 ],
            [ 'dmap.updatetype' =>  0 ],
            [ 'dmap.specifiedtotalcount' =>  1 ],
            [ 'dmap.returnedcount' => 1 ],
            [ 'dmap.listing' => [
                [ 'dmap.listingitem' => [
                    [ 'dmap.itemid' =>  35 ],
                    [ 'dmap.persistentid' => '13950142391337751523' ],
                    [ 'dmap.itemname' => $self->name ],
                    [ 'dmap.itemcount' => scalar keys %{ $self->tracks } ],
                    [ 'dmap.containercount' =>  1 ],
                   ],
                 ],
               ],
             ],
           ]]] ));
}

sub database_items {
    my $self = shift;
    my $database_id = shift;
    my $tracks = $self->_all_tracks;
    return $self->_dmap_pack( [[ 'daap.databasesongs' => [
        [ 'dmap.status' => 200 ],
        [ 'dmap.updatetype' => 0 ],
        [ 'dmap.specifiedtotalcount' => scalar @$tracks ],
        [ 'dmap.returnedcount' => scalar @$tracks ],
        [ 'dmap.listing' => $tracks ]
       ]]] );
}

sub database_playlists {
    my $self = shift;
    my $database_id = shift;

    my $tracks = $self->_all_tracks;
    return $self->_dmap_pack( [[ 'daap.databaseplaylists' => [
        [ 'dmap.status'              => 200 ],
        [ 'dmap.updatetype'          =>   0 ],
        [ 'dmap.specifiedtotalcount' =>   1 ],
        [ 'dmap.returnedcount'       =>   1 ],
        [ 'dmap.listing'             => [
            [ 'dmap.listingitem' => [
                [ 'dmap.itemid'       => 39 ],
                [ 'dmap.persistentid' => '13950142391337751524' ],
                [ 'dmap.itemname'     => $self->name ],
                [ 'com.apple.itunes.smart-playlist' => 0 ],
                [ 'dmap.itemcount'    => scalar @$tracks ],
               ],
             ],
           ],
         ],
       ]]] );
}

sub playlist_items {
    my $self = shift;
    my $database_id = shift;
    my $playlist_id = shift;

    my $tracks = $self->_all_tracks;
    $self->_dmap_pack( [[ 'daap.playlistsongs' => [
        [ 'dmap.status' => 200 ],
        [ 'dmap.updatetype' => 0 ],
        [ 'dmap.specifiedtotalcount' => scalar @$tracks ],
        [ 'dmap.returnedcount'       => scalar @$tracks ],
        [ 'dmap.listing' => $tracks ]
       ]]] );
}



sub item_field {
    my $self = shift;
    my $track = shift;
    my $field = shift;

    (my $method = $field) =~  s{[.-]}{_}g;
    # kludge
    if ($field =~ /dpap\.(thumb|hires)/) {
        $field = 'dpap.picturedata';
    }

    [ $field => eval { $track->$method() } ]
}


sub response_tracks {
    my $self = shift;
}

sub uniq {
    my %seen;
    return grep { !$seen{$_}++ } @_;
}

# some things are always present in the listings returned, whether you
# ask for them or not
sub _always_answer {
    qw( dmap.itemkind dmap.itemid dmap.itemname );
}

sub _response_fields {
    my $self = shift;

    my $meta = { $self->_uri_arguments }->{meta} || '';
    my @fields = uniq $self->_always_answer, split /(?:,|%2C)/, $meta;
    return @fields;
}

sub _uri_arguments {
    my $self = shift;
    my @chunks = split /&/, $self->uri->query || '';
    return map { split /=/, $_, 2 } @chunks;
}

sub _all_tracks {
    my $self = shift;

    # sometimes, all isn't really all (DPAP)
    my $query = { $self->_uri_arguments }->{query} || '';
    my @tracks = $query =~ /dmap\.itemid/
      ? map { $self->tracks->{$_} } $query =~ /dmap\.itemid:(\d+)/g
      : values %{ $self->tracks };

    my @fields = $self->_response_fields;
    my @results;
    for my $track (@tracks) {
        push @results, [ 'dmap.listingitem' => [
            map { $self->item_field( $track => $_ ) } @fields ] ];
    }
    return \@results;
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
