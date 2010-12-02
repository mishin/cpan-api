package Plack::Middleware::CPANSource;

use parent qw( Plack::Middleware );

use Archive::Tar::Wrapper;
use File::Copy;
use File::Path qw(make_path);
use Furl;
use JSON::DWIW;
use Modern::Perl;
use Path::Class qw(file);

sub call {
    my ( $self, $env ) = @_;

    if ( $env->{REQUEST_URI} =~ m{\A/source/(\w*)/([^\/\?]*)/(.*)} ) {
        
        my ( $pauseid, $distvname, $file ) = ( $1, $2, $3 );
        
        my $archive = $self->get_archive_name( $pauseid, $distvname );
        return $self->app->( $env ) if !$archive;

        my $new_path
            = $self->file_path( $pauseid, $distvname, $archive, $file );
say $new_path;
        $env->{PATH_INFO} = $new_path if $new_path;
    }

    return $self->app->( $env );
}

sub get_archive_name {

    my ( $self, $pauseid, $distvname ) = @_;

    my $furl = Furl->new( timeout => 10, );
    my $res = $furl->get(
        "http://localhost:9200/cpan/module/_search?q=distvname:$distvname" );

    my $found  = JSON::DWIW->from_json( $res->content );
    my $module = $found->{hits}->{hits}->[0]->{_source};
    my $id     = $module->{pauseid} ? $module->{pauseid} : $module->{author};

    return if ( !$module || $pauseid ne $id );
    return $module->{archive};

}

sub file_path {

    my ( $self, $pauseid, $distvname, $archive, $file ) = @_;

    my $base_folder   = '/home/olaf/cpan-source/';
    my $author_folder = $self->pauseid2folder( $pauseid );
    my $rewrite_path  = "$author_folder/$distvname/$file";
    my $dest_file     = $base_folder . $rewrite_path;

    return $rewrite_path if ( -e $dest_file );

    my $path = "/home/cpan/CPAN/authors/id/$archive";
    return if ( !-e $path );

    my $arch = Archive::Tar::Wrapper->new();
    $arch->read( $path );
    $arch->list_reset();

    while ( my ( $tar_path, $phys_path ) = @{ $arch->list_next } ) {

        next if ( $tar_path !~ m{$file\z} );
        
        make_path( file( $dest_file )->dir, {} );
        copy( $phys_path, $dest_file );
        return $rewrite_path;
    }

    return;

}

sub pauseid2folder {

    my $self = shift;
    my $id   = shift;
    return sprintf( "id/%s/%s/%s/",
        substr( $id, 0, 1 ),
        substr( $id, 0, 2 ), $id );

}

1;

=pod

=head2 file_path( $pauseid, $distvname, $archive, $file )

    print $self->file_path( 'IONCACHE', 'Plack-Middleware-HTMLify-0.1.1', 'I/IO/IONCACHE/Plack-Middleware-HTMLify-0.1.1.tar.gz', 'lib/Plack/Middleware/HTMLify.pm' );
    # id/I/IO/IONCACHE/Plack-Middleware-HTMLify-0.1.1/lib/Plack/Middleware/HTMLify.pm
    
=head2 get_archive_name( $pauseid, $distvname )

Returns the name of the distribution archive file.  For example:

    my $pkg = $self->get_archive_name( 'IONCACHE', 'Plack-Middleware-HTMLify-0.1.1' );
    print $pkg; # I/IO/IONCACHE/Plack-Middleware-HTMLify-0.1.1.tar.gz

=head2 pauseid2folder

    print $self->pausid2folder( 'IONCACHE' );
    # id/I/IO/IONCACHE/

=cut