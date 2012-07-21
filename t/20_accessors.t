# $Id$

use strict;
use warnings;

use Test::More;

require DateTimeX::Fiscal::Fiscal5253;
my $class = 'DateTimeX::Fiscal::Fiscal5253';

# This script only tests the accessors and not the values generated
# for the object other than the year parameter. Another script
# will perform those tests.

# Get an object for testing with. Use values different from defaults
# to ensure the accessors are fetching real information.
my %params = (
    year => 2014,
    end_month => 1,
    end_dow => 1,
    end_type => 'closest',
    leap_period => 'first'
);

my $fc = $class->new( %params );

# Preparing an array of test cases makes it slightly easier, IMHO, to
# see what cases are being covered.
my @accessors = (
    {
        accessor => 'year',
        expect => $params{year},
    },
    {
        accessor => 'end_month',
        expect => $params{end_month},
    },
    {
        accessor => 'end_dow',
        expect => $params{end_dow},
    },
    {
        accessor => 'end_type',
        expect => $params{end_type},
    },
    {
        accessor => 'leap_period',
        expect => $params{leap_period},
    },
    {
        accessor => 'start',
        expect => '2013-01-29',
    },
    {
        accessor => 'end',
        expect => '2014-02-03',
    },
    {
        accessor => 'weeks',
        expect => '53',
    },
);

my $testplan = @accessors * 2;
$testplan += 2;
$testplan *= 2;

plan( tests => $testplan );

# First, test the "meta" method, not really an accessor as it will
# return either a hash or a hash reference depending upon context
# containing all of the information that can be returned by an accessor.
my $yr_ref = $fc->meta();
isa_ok($yr_ref,'HASH','get hash reference for meta data');

# This assumes that if we can access a particular item we got a hash.
my %yr_hash = $fc->meta();
ok($yr_hash{year} == $params{year},'get hash for meta data');

# Test fetching the values. This tests that the accessors retrieve
# known values from the proper elements in the object.
foreach ( @accessors ) {
    my $accessor = $_->{accessor};
    ok($fc->$accessor() eq $_->{expect},"get $accessor");
}

# Now test that trying to change a parameter value will emit a "croak"
foreach ( @accessors ) {
    my $accessor = $_->{accessor};
    eval {
        my $foo = $fc->$accessor($_->{expect});
    };
    like($@,qr/$accessor/,"blocked setting $accessor");
}

# Now do it all over again using the Empty::Fiscal5253 class to be sure
# this module can be safely sub-classed. A single test of the basic
# constructor would probably suffice, but why not be sure?

$class = 'Empty::Fiscal5253';

$yr_ref = $fc->meta();
isa_ok($yr_ref,'HASH','get hash reference for meta data');

%yr_hash = $fc->meta();
ok($yr_hash{year} == $params{year},'get hash for meta data');

foreach ( @accessors ) {
    my $accessor = $_->{accessor};
    ok($fc->$accessor() eq $_->{expect},"get $accessor");
}

foreach ( @accessors ) {
    my $accessor = $_->{accessor};
    eval {
        my $foo = $fc->$accessor($_->{expect});
    };
    like($@,qr/read\-only param/,"blocked setting $accessor");
}

exit;

# package for empty package tests
package Empty::Fiscal5253;
use base qw(DateTimeX::Fiscal::Fiscal5253);

__END__
