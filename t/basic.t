#!/usr/bin/env perl
use Test2::V0;
use Plack::Test;
use HTTP::Request;
use JSON;
use Types::Standard -types;
use strictures 2;

use Starch::Remote::Service;

my $app = Starch::Remote::Service->new(
    starch => {
        store => { class => '::Memory' },
        plugins => ['::CookieArgs'],
    },
    validate_res => 1,
)->to_app();

my $tester = Plack::Test->create( $app );

subtest '/' => sub{
    subtest GET => sub{
        my $res = req( GET => '/' );
        test_res( $res, code=>404 );
    };
};

subtest '/begin' => sub{
    foreach my $verb (qw( GET PUT DELETE )) {
        subtest $verb => sub{
            my $res = req( $verb => '/begin' );
            test_res( $res, code=>404 );
        };
    }

    subtest POST => sub{
        subtest 'no content' => sub{
            my $res = req( POST => '/begin' );
            test_res( $res, code=>400, content=>qr{invalid JSON} );
        };
        subtest 'invalid JSON' => sub{
            my $res = req( POST => '/begin', [], '{' );
            test_res( $res, code=>400, content=>qr{invalid JSON} );
        };
        subtest 'incorrectly structured JSON' => sub{
            my $res = req( POST => '/begin', [], '{"bad":false}' );
            test_res( $res, code=>400, content=>qr{incorrectly structured JSON} );
        };

        subtest 'new session' => sub{
            my $res = req( POST => '/begin', [], '{"headers":[]}' );
            test_res( $res, code=>200 );
        };
    };
};

my $finish_res_type = Dict[
    headers => ArrayRef[ Str ],
];

done_testing;

sub req {
    return $tester->request( HTTP::Request->new( @_ ) );
}

sub test_res {
    my $res = shift;

    while (@_) {
        my $method = shift;
        my $expected = shift;
        if (ref($expected) eq 'Regexp') {
            like( $res->$method(), $expected, "$method like $expected" );
        }
        else {
            is( $res->$method(), $expected, "$method is $expected" );
        }
    }

    return;
}
