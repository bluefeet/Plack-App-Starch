package Plack::App::Starch;

=head1 NAME

Plack::App::Starch - Expose your Starch setup as a REST API.

=head1 SYNOPSIS

Create a C<starch.psgi> file:

    use Plack::App::Starch;
    
    Plack::App::Starch->new(
        starch => {
            store => {
                class => '::Memory',
            },
        },
    )->to_app();

Then launch it:

    plackup starch.psgi

And make requests against it:

    curl -X PUT -H 'Content-Type: application/json' -d '{"bar":2}' http://0:5000/states/foo
    curl -X GET http://0:5000/states/foo
    curl -X DELETE http://0:5000/states/foo

=head1 DESCRIPTION

This L<Plack> application exposes L<Starch> as a REST API allowing for
remote modification of Starch states.

This is useful when, for example, you are using starch as your backend for
Catalyst sessions (via L<Catalyst::Plugin::Starch>) and you would like to
allow another service, perhaps even one written in another language, to
access the sessions.

=head1 ARGUMENTS

=head2 starch

This can be either a L<Starch> object, or arguments to create one.

=head1 API ENDPOINTS

=head2 GET /states/:id

Returns a C<200> response with the state's data as JSON in the response body.

=head2 PUT /states/:id

Expects the request content to be JSON and uses it to set the state's data.

Returns a C<204>.

=head2 DELETE /states/:id

Deletes the state.

Returns a C<204>.

=cut

use Starch;
use JSON;
use Plack::Request;
use Scalar::Util qw( blessed );
use Try::Tiny;

use strictures 2;
use namespace::clean;

use parent 'Plack::Component';

use Plack::Util::Accessor qw(
    starch
);

my $json = JSON->new();

sub prepare_app {
    my ($self) = @_;

    my $starch = $self->starch();
    die "The starch argument is required" if !$starch;

    if (!blessed $starch) {
        $starch = Starch->new( $starch );
        $self->starch( $starch );
    }

    return;
}

sub call {
    my ($self, @args) = @_;

    return try {
        $self->_do_actual_call( @args )
    }
    catch {
        warn $_;

        [
            500,
            ['Content-Type' => 'text/plain'],
            ['Internal Server Error'],
        ];
    };
}

sub _do_actual_call {
    my ($self, $env) = @_;

    my $verb = $env->{REQUEST_METHOD};
    my $path = $env->{PATH_INFO};

    if ($path =~ m{^/states/([^/]+)$}) {
        my $id = $1;
        my $state = $self->starch->state( $id );

        if ($verb eq 'GET') {
            return [
                200,
                ['Content-Type' => 'application/json'],
                [ $json->encode( $state->data() ) ],
            ];
        }
        elsif ($verb eq 'PUT') {
            my $req = Plack::Request->new( $env );
            my $new_data = $json->decode( $req->content() );
            %{ $state->data() } = %$new_data;
            $state->save();
            return [ 204, [], [] ];
        }
        elsif ($verb eq 'DELETE') {
            $state->delete();
            return [ 204, [], [] ];
        }
    }

    return [404, ['Content-Type' => 'text/plain'], ['Not Found']];
}

1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeetE<64>gmail.com>

=head1 ACKNOWLEDGEMENTS

Thanks to L<ZipRecruiter|https://www.ziprecruiter.com/>
for encouraging their employees to contribute back to the open
source ecosystem.  Without their dedication to quality software
development this distribution would not exist.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

