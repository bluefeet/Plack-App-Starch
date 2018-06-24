#!/usr/bin/env perl
use Test2::V0;
use Plack::Test;
use HTTP::Request;
use JSON;
use Types::Standard -types;
use strictures 2;

{
    package Failing::Starch::Remote::Service;
    use Types::Standard -types;
    use Moo;
    extends 'Starch::Remote::Service';
    my $def_begin_res_type = Dict[
        id   => Str,
        data => Dict[ foo=>Str ],
    ];
    sub _begin_res_type { $def_begin_res_type }
}

my @tests = (
    [ 0, 1 ],
    [ 1, 1 ],
    [ 0, 0 ],
    [ 1, 0 ],
);

foreach my $test (@tests) {
    my ($validate_res, $should_fail) = @$test;

    my $class = $should_fail ? 'Failing::Starch::Remote::Service' : 'Starch::Remote::Service';

    my $app = $class->new(
        starch => {
            store => { class => '::Memory' },
            plugins => ['::CookieArgs'],
        },
        validate_res => $validate_res,
    )->to_app();

    my $tester = Plack::Test->create( $app );

    my $res = req( $tester, POST => '/begin', [], '{"headers":[]}' );

    subtest
        'res validation ' . ($validate_res ? 'on' : 'off') .
        ' and is' . ($should_fail ? '' : ' not') . ' failing'
    => sub{
        test_res( $res, code => ($validate_res and $should_fail) ? 500 : 200 );
    }
}

done_testing;

sub req {
    my $tester = shift;
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
