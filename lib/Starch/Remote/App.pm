package Starch::Remote::App;

=head1 NAME

Starch::Remote::App - A plack application for running the Starch remote service.

=head1 SYNOPSIS

Create a C<starch-remote.psgi> file:

    use Starch::Remote::App;
    
    Starch::Remote::App->new(
        starch => {
            store => { class => '::Memory' },
            plugins => ['::CookieArgs'],
        },
    )->to_app();

Then launch it:

    plackup starch-remote.psgi

=head1 DESCRIPTION

This L<Plack> service exposes L<Starch> in a way that allows for mostly
hands-free integration of Starch with disparate HTTP applications, including
applications written in other languages.  Having a central engine for
managing sessions can be especially important in polyglot organizations,
allowing for web applications to be written in multiple languages yet
still share the same session backend and logic.

=head1 INTEGRATION

The typical setup is an arbitrary web application which needs to access
sessions as part of handling a request.  This web application has no knowledge
of how sessions are stored or how they are tracked.  In order to retrofit
the web application to use the Starch remote a request would be handled
like this:

=over

=item 1

A request is begun in the web application.

=item 2

The web application issues a C<POST> subrequest agains the C</begin> endpoint
of the Starch remote service.  The C<POST> subrequest includes all
HTTP headers that the web application received in it's request.

=item 3

The Starch remote's response includes the L<Starch::State/id> and the
L<Starch::State/data> of the session.  If no C<id> could be derived from
the hedaers supplied in the subrequest then a new state will be created and
it's C<id> and empty C<data> will be returned.

=item 4

The web application's main logic steps in and handles the request.  The web
application will read, and potentially, write to the C<data> hash as needed.

=item 5

When the web application is ready to send response headers back to the client
it issues a C<POST> subrequest agains the C</finish> endpoint of the Starch
remote service.  The C<POST> subrequest includes the C<id> and C<data>
originally supplied in step #3, but the C<data> may have been modified during
step #4.

=item 6

The Starch remote's response to the subrequest contains HTTP headers for the
web application to include in it's response to the request.

=item 7

And, finally, the web application returns a response.

=back

See the L</ENDPOINTS> documentation with example of the 

=head1 CLIENTS

L<Starch::Remote::Client> is a client for this service.

L<Catalyst::Plugin::Starch::Remote> causes Catalyst to use this
service for sessions retrieval and storage.

=head1 REQUIRED ARGUMENTS

=head2 starch

    Starch::Remote::App->new(
        starch => {
            store => { class => '::Memory' },
            plugins => [ '::CookieArgs' ],
        },
    );

This may be either a L<Starch> object, or hashref arguments to create one.

The L<Starch::Plugin::CookieArgs> plugin is required.

=head1 ENDPOINTS

=head2 POST /begin

Expects the request content to be a JSON object with a single key, `headers`,
containing an array of all HTTP headers that the caller received.

Returns a JSON object with the `id` key set to the ID of the Starch state, and
a `data` key containing the state data.

Example request content:

    {
        "headers": [
            "Acccept-Language", "en-us",
            "Cookie", "session=4f29abc0917cb119a86c8b15e70503a4380667bf"
        ]
    }

Example response content:

    {
        "id": "4f29abc0917cb119a86c8b15e70503a4380667bf",
        "data": {"foo":1}
    }

=head2 POST /finish

Expects the request content to be a JSON object with the `id` key set to the ID
of the Starch state, and the `data` key set to the new state data to be saved.

Returns a JSON object with the `headers` key set to an array of key/value pairs.

Example request content:

    {
        "id": "4f29abc0917cb119a86c8b15e70503a4380667bf",
        "data": {"foo":1,"bar":2}
    }

Example response content:

    {
        "headers": [
            "Set-Cookie",
            "session=4f29abc0917cb119a86c8b15e70503a4380667bf; domain=.example.com; path=/; ..."
        ]
    }

=cut

use Starch;
use JSON;
use Plack::Request;
use Scalar::Util qw( blessed );
use Try::Tiny;
use HTTP::Headers::Fast;
use Cookie::Baker;
use Types::Standard -types;

use strictures 2;
use namespace::clean;

use parent 'Plack::Component';

use Plack::Util::Accessor qw(
    starch
    does_cookie_args
);

my $json;

sub _detach {
    my ($self, $res) = @_;
    die ['STARCH-REMOTE-APP-DETACH',$res];
}

sub prepare_app {
    my ($self) = @_;

    $json = JSON->new();

    my $starch = $self->starch();
    die "The starch argument is required" if !$starch;

    if (!blessed $starch) {
        $starch = Starch->new( $starch );
        $self->starch( $starch );
    }

    die 'The Starch object does not support the cookie_name method (from Starch::Plugin::CookieArgs)'
        if !$starch->can('cookie_name');

    die 'The Starch state objects do not support the cookie_args method (from Starch::Plugin::CookieArgs)'
        if !$starch->state->can('cookie_args');

    return;
}

sub call {
    my ($self, @args) = @_;

    my $res = try {
        return $self->_dispatch( @args )
    }
    catch {
        return $_->[1] if ref($_) eq 'ARRAY' and $_->[0] and $_->[0] eq 'STARCH-REMOTE-APP-DETACH';

        warn $_;

        return [
            500,
            ['Content-Type' => 'text/plain'],
            ['Internal Server Error'],
        ];
    };

    $res ||= [404, ['Content-Type' => 'text/plain'], ['Not Found']];

    return $res;
}

sub _dispatch {
    my ($self, $env) = @_;

    my $starch = $self->starch();
    my $req = Plack::Request->new( $env );
    my $path = $req->path();
    my $verb = $req->method();

    if ($path eq '/begin') {
        return $self->_post_begin( $req ) if $verb eq 'POST';
    }
    elsif ($path eq '/finish') {
        return $self->_post_finish( $req ) if $verb eq 'POST';
    }

    return undef;
}

sub _decode_req_content {
    my ($self, $req, $type) = @_;

    my $json = $req->content();
    my $content = try {
        return $json->decode( $json );
    }
    catch {
        $self->_detach([
            400,
            ['Content-Type' => 'text/plain'],
            ['The request content contained invalid JSON: ' . $_],
        ]);
    };

    my $error = $type->validate( $content );
    return $content if !defined $error;

    $self->_detach([
        400,
        ['Content-Type' => 'text/plain'],
        ['The request content contained incorrectly structured JSON: ' . $error],
    ]);
}

my $begin_req_type = Dict[
    headers => ArrayRef[ Str ],
];

sub _post_begin {
    my ($self, $req) = @_;

    my $input = $self->_decode_req_content( $req, $begin_req_type );
    $headers = HTTP::Headers::Fast->new( @{ $input->{headers} } );

    my $cookies = crush_cookie( $headers->header('Cookie') );
    my $id = $cookies->{ $starch->cookie_name() };
    my $state = $starch->state( $id );

    my $output = {
        id => $state->id(),
        data => $state->data(),
    };

    return [
        200,
        ['Content-Type' => 'application/json'],
        [ $json->encode( $output ) ],
    ];
}

my $finish_req_type = Dict[
    id   => Str,
    data => HashRef,
];

sub _post_finish {
    my ($self, $req) = @_;

    my $input = $self->_decode_req_content( $req, $begin_req_type );

    my $starch = $self->starch();
    my $state = $starch->state( $input->{id} );
    %{ $state->data() } = %{ $input->{data} };
    $state->save();

    my $output = {
        headers => [
            'Set-Cookie' => bake_cookie(
                $starch->cookie_name(),
                $state->cookie_args(),
            ),
        ],
    };

    return [
        200,
        ['Content-Type' => 'application/json'],
        [ $json->encode( $output ) ],
    ];
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

