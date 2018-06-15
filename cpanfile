requires 'strictures' => '2.000003';
requires 'namespace::clean' => '0.27';

requires 'Starch' => '0.07';
requires 'HTTP::Headers::Fast' => '0.12';
requires 'Cookie::Baker' => '0.06';
requires 'Types::Standard' => '1.002001';
requires 'JSON' => '2.59';
requires 'Try::Tiny' => '0.28';

# We don't depend on Plack.pm directly, but it is the only module in the Plack
# distro which has a version.
requires 'Plack' => '1.0000';
requires 'Plack::Request';
requires 'Plack::Component';
requires 'Plack::Util::Accessor';

requires 'Scalar::Util';

on test => sub {
    requires 'Test2::V0' => '0.000094';
};
