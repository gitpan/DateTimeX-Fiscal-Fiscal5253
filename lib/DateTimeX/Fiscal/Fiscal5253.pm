# $Id$

package DateTimeX::Fiscal::Fiscal5253;

use strict;
use warnings;

our $VERSION = '0.04';

# This enables trace messages to be used by the test suite.
our $TRACE = 0;

use Carp;
use Data::Dumper;
use DateTime;
use POSIX qw( strftime );

my $pkg = __PACKAGE__;

my @params = qw(
    end_month
    end_dow
    end_type
    leap_period
    year
    date
);

my $defaults = {
    end_month => 12,
    end_dow => 6,
    end_type => 'last',
    leap_period => 'last',
};

my @periodmonths = qw(
  January
  February
  March
  April
  May
  June
  July 
  August
  September
  October
  November
  December
);

# Utility function to validate values supplied as a calendar style.
my $_valid_cal_style = sub {
    my $style = shift;

    my $cal = lc($style) || 'fiscal';
    if ( $cal ne 'fiscal' && $cal ne 'restated' && $cal ne 'truncated' ) {
        carp "Invalid calendar style specified: $cal";
        return;
    }

    return $cal;
};

# Utility function to covert a date string to a DT object
sub _str2dt
{
    my $date = shift;

    # convert date param to DT object
    my ($y,$m,$d);
    if ( $date =~ m/(^\d{4})\-(\d{1,2})\-(\d{1,2})($|\D+)/ ) {
        $y = $1, $m = $2, $d = $3;
    } elsif ( $date =~ m/^(\d{1,2})\/(\d{1,2})\/(\d{4})($|\D+)/ ) {
        $y = $3, $m = $2, $d = $1;
    } else {
        carp "Unable to parse date string: $date";
        return;
    }
    eval {
        $date = DateTime->new( year => $y, month => $m, day => $d );
    };
    if ( $@ ) {
        carp "Invalid date: $date";
        return;
    }

    return $date;
}

# This code ref builds the basic calendar structures as needed.
my $_build_periods = sub {
    my $self = shift;
    my $style = shift || 'fiscal';

    # not strictly needed, but makes for easier to read code
    my $restate = $style eq 'restated' ? 1 : 0;
    my $truncate = $style eq 'truncated' ? 1 : 0;

    # Avoid expensive re-builds when possible.
    return if $restate && defined($self->{_restated});
    return if $truncate && defined($self->{_truncated});
    return if $style eq 'fiscal' && defined($self->{_fiscal});

    # Disabled this for now, becomes problematic for various
    # methods such as "contains" in normal years.
    # return if ($restate || $truncate) && $self->{_weeks} == 52;

    carp "Data for a $style calendar will be generated\n" if $TRACE;

    my $pstart = $self->{_start}->clone;

    # This value is confusing only because it is 0-based unlike
    # the other month values.
    my $p1month = $self->{end_month} == 12 ? 0 : $self->{end_month};
    my @pweeks = (4, 4, 5, 4, 4, 5, 4, 4, 5, 4, 4, 5);
    my $wkcnt = 52;

    # a truncated structure ignores the last week in a 53 week year
    if ( $self->has_leap_week && !$truncate ) {
        if ( $restate ) {
            # ignore the fist week and treat as any other 52 week year
            $pstart->add( days => 7 );
        } elsif ( $self->{leap_period} eq 'first' ) {
            $pweeks[$p1month] += 1;
            $wkcnt = 53;
        } else {
            $pweeks[$self->{end_month} - 1] += 1;
            $wkcnt = 53;
        }
    }

    my $pdata  = {
        meta => {
        style => $style,
        year => $self->{year},
        end_month => $self->{end_month},
        end_dow => $self->{end_dow},
        end_type => $self->{end_type},
        leap_period => $self->{leap_period},
        weeks => $wkcnt,
        start => $pstart->ymd,
        end => undef, # this is set after the cache is built
        }
    };

    for (0 .. 11) {
        my $p_index = ($p1month + $_) % 12;

        $pdata->{$_ + 1} = {
            period => $_ + 1,
            start   => $pstart->ymd,
            weeks    => $pweeks[$p_index],
            month    => $periodmonths[$p_index]
        };

        $pstart->add(weeks => $pweeks[$p_index]);

        my $pend = $pstart->clone->subtract(days => 1);
        $pdata->{$_ + 1}->{end} = $pend->ymd;
    }
    $pdata->{meta}->{end} = $pdata->{12}->{end};

    if ( $self->{_weeks} == 52 ) {
        # Set style to 'fiscal' and assign the structure to all
        # three calendar types in a normal year to save time and space.
        $pdata->{meta}->{style} = 'fiscal';
        $self->{_fiscal} = $self->{_restated} = $self->{_truncated} = $pdata;
    } else {
        $self->{"_$style"} = $pdata;
    }

    $self->{_stale} = 0;

    return;
};

# The end day for a specified year is trivial to determine. In normal
# accounting use, a fiscal year is named for the calendar year it ends in,
# not the year it begins.
sub _end5253
{
    my $args = shift;

    my $dt = DateTime->last_day_of_month(
        year => $args->{year},
        month => $args->{end_month},
        time_zone => 'floating'
    );

    my $eom_day = $dt->day;
    my $dt_dow = $dt->dow;

    if ( $dt_dow > $args->{end_dow} ) {
        $dt->subtract( days => $dt_dow - $args->{end_dow} );
    } elsif ( $dt_dow < $args->{end_dow} ) {
        $dt->subtract( days => ($dt_dow + 7) - $args->{end_dow} );
    }
    $dt->add( weeks => 1 )
        if $args->{end_type} eq 'closest' && $eom_day - $dt->day > 3;

    return $dt;
}

# Finding the starting day for a specified year is easy. Simply find
# the last day of the preceding year since the year is defined by
# the ending day and add 1 day to that. This avoids calendar year and month
# boundary issues.
sub _start5253
{
    my $args = shift;

    $args->{year} -= 1;
    my $dt = _end5253($args)->add( days => 1 );
    $args->{year} += 1; # don't forget to do this!

    return $dt;
}

# Determine the correct fiscal year for any given date
sub _find5253
{
    my $args = shift;

    my $y1 = $args->{date}->year;

    # do not assume it is safe to change the year attribute
    local($args->{year});
    $args->{year} = $y1;

    my $e1 = _end5253($args);
    return $y1 + 1 if $e1 < $args->{date};

    my $s1 = _start5253($args);
    return $y1 - 1 if $s1 > $args->{date};

    return $y1;
}

# Duh
sub new
{
    my $proto = shift;
    my %args = @_;

    # normalize end_type arg
    $args{end_type} = lc($args{end_type}) if exists $args{end_type};
    # normalize leap_period arg
    $args{leap_period} = lc($args{leap_period}) if exists $args{leap_period};

    # do basic validation and set controlling params as needed
    # the default is to end on the last Saturday of December
    foreach ( keys(%{$defaults}) ) {
        $args{$_} = $defaults->{$_} if !defined($args{$_});
    }
    if ( $args{end_type} ne 'last' && $args{end_type} ne 'closest' ) {
        carp "Invalid value for param end_type: $args{end_type}";
        return;
    }
    if ( $args{end_month} < 1 || $args{end_month} > 12 ) {
        carp "Invalid value for param end_month: $args{end_month}";
        return;
    }
    if ( $args{end_dow} < 1 || $args{end_dow} > 7 ) {
        carp "Invalid value for param end_dow: $args{end_dow}";
        return;
    }
    if ( $args{leap_period} ne 'first' && $args{leap_period} ne 'last' ) {
        carp "Invalid value for param leap_period: $args{leap_period}";
        return;
    }

    if ( $args{year} && $args{date} ) {
        # which one would be correct?
        carp 'Mutually exclusive parameters "year" and "date" present';
        return;
    } elsif ( ref($args{date}) && $args{date}->isa('DateTime') ) {
        $args{date} = $args{date}->clone;
    } elsif ( ref($args{date}) ) {
        carp 'Object in "date" parameter is not a member of DateTime';
        return;
    } elsif ( $args{date} ) {
        return unless $args{date} = _str2dt($args{date});
    } elsif ( !$args{year} ) {
        $args{date} = DateTime->today() unless $args{year};
    }

    my $class = ref($proto) || $proto;
    my $self = bless {
        _stale => 1,
        _fiscal => undef,
        _restated => undef,
        _truncated => undef,
    }, $class;
    foreach ( @params ) {
        $self->{$_} = $args{$_};
        delete($args{$_});
    };
    if ( scalar(keys(%args)) ) {
        carp 'Unknown parameter(s): '.join(',',keys(%args));
        return;
    }

    if ( $self->{date} ) {
        $self->{date}->truncate( to => 'day' )->set_time_zone( 'floating' );
        $self->{year} = _find5253($self);
    }
    $self->{_start} = _start5253($self);
    $self->{_start_ymd} = $self->{_start}->ymd;
    $self->{_end} = _end5253($self);
    $self->{_end_ymd} = $self->{_end}->ymd;

    $self->{_weeks} =
        $self->{_start}->clone->add( days => 367 ) > $self->{_end} ? 52 : 53;

    &{$_build_periods}($self,'fiscal');

    return $self;
}

# return the meta data about the underlying object.
sub meta
{
    my $self = shift;

    my %fyear = (
        year => $self->{year},
        end_month => $self->{end_month},
        end_dow => $self->{end_dow},
        end_type => $self->{end_type},
        leap_period => $self->{leap_period},
        start => $self->{_start_ymd},
        end => $self->{_end_ymd},
        weeks => $self->{_weeks},
    );

    return wantarray ? %fyear : \%fyear;
}

sub year
{
    my $self = shift;

    croak "FATAL ERROR: Trying to set read-only param year" if @_;

    return $self->{year};
}

sub end_month
{
    my $self = shift;

    croak "FATAL ERROR: Trying to set read-only param end_month" if @_;

    return $self->{end_month};
}

sub end_dow
{
    my $self = shift;

    croak "FATAL ERROR: Trying to set read-only param end_dow" if @_;

    return $self->{end_dow};
}

sub end_type
{
    my $self = shift;

    croak "FATAL ERROR: Trying to set read-only param end_type" if @_;

    return $self->{end_type};
}

sub leap_period
{
    my $self = shift;

    croak "FATAL ERROR: Trying to set read-only param leap_period" if @_;

    return $self->{leap_period};
}

sub start
{
    my $self = shift;

    croak "FATAL ERROR: Trying to set read-only param _start_ymd" if @_;

    return $self->{_start_ymd};
}

sub end
{
    my $self = shift;

    croak "FATAL ERROR: Trying to set read-only param _end_ymd" if @_;

    return $self->{_end_ymd};
}

sub weeks
{
    my $self = shift;

    croak "FATAL ERROR: Trying to set read-only param _weeks" if @_;

    return $self->{_weeks};
}

sub has_leap_week
{
    my $self = shift;

    return ($self->{_weeks} == 53 ? 1 : 0);
}

sub contains
{
    my $self = shift;
    my %args = @_;

    return unless my $cal = &{$_valid_cal_style}($args{calendar});

    # Yes, a DT oject set to "today" would work, but this is faster.
    $args{date} = strftime("%Y-%m-%d",localtime())
       if !$args{date} || lc($args{date}) eq 'today';

    return unless my $date = _str2dt($args{date})->ymd;

    &{$_build_periods}($self,$cal);

    my $phash = $self->{"_$cal"};
    return if $date lt $phash->{1}->{start} || $date gt $phash->{12}->{end};

    # since the date is in the calendar, let's return it's period
    my $p;
    for ( $p = 1; $date gt $phash->{$p}->{end}; $p++ ) {
        if ( $p > 12 ) {
            # this should NEVER happen
            croak "FATAL ERROR! RAN OUT OF PERIODS";
        }
    }

    return $p;
}

# This method transforms the hash in _fiscal, _restated or _truncated
# into an array with metadata in the first element.
sub calendar
{
    my $self = shift;
    my %args = @_;

    return unless my $style = &{$_valid_cal_style}($args{style});

    &{$_build_periods}($self,$style);
    my $pdata = $self->{"_$style"};

    my @calendar = (
        $pdata->{meta}
    );

    for ( 1 .. 12 ) {
        push(@calendar,$pdata->{$_});
    }

    return wantarray ? @calendar : \@calendar;
}

sub period
{   
    my $self   = shift;
    my %args = @_;

    return unless my $cal = &{$_valid_cal_style}($args{calendar});

    # guard against the pathological case of $args{period} == undef
    if ( exists($args{period}) && !defined($args{period}) ) {
        carp "param 'period' exists but has has a value of 'undef'";
        return;
    }
    my $pnum = defined($args{period}) ? $args{period} : 0;
    if ( $pnum < 0 || $pnum > 12 ) {
        carp "Invalid period specified";
        return;
    }

    &{$_build_periods}($self,$cal);
    my $chash = $self->{"_$cal"};

    # Things get interesting if the current date is NOT in the fiscal
    # year described by the object. Best to just return an error if
    # that is the case.
    if (!$pnum) {
        my $ymd = DateTime->now( time_zone => 'floating' )->ymd;
        if ( !($pnum = $self->contains( date => $ymd, calendar => $cal )) ) {
            carp 'Today\'s date is not in this object\'s fiscal year';
            return;
        }
    }

    my %phash = %{$chash->{$pnum}};
    $phash{period} = $pnum;

    return wantarray ? %phash : \%phash;
}

# Utiliy routine, hidden from public use, to prevent duplicate code in
# the period attribute accessors.
my $_period_attr = sub {
    my $self = shift;
    my $attr = shift;
    my %args = @_;

    my $pnum =
      defined($args{period}) ? $args{period} : $self->period;
    if ( $pnum < 1 || $pnum > 12 ) {
        carp "Invalid period specified: $args{period}";
        return;
    }

    return unless my $cal = &{$_valid_cal_style}($args{calendar});

    &{$_build_periods}($self,$cal);
    my $chash = $self->{"_$cal"};

    return $chash->{$pnum}->{$attr};
};

sub period_month
{
    my $self = shift;

    return &{$_period_attr}( $self,'month',@_ );
}

sub period_start
{
    my $self = shift;

    return &{$_period_attr}( $self,'start',@_ );
}

sub period_end
{
    my $self = shift;

    return &{$_period_attr}( $self,'end',@_ );
}

sub period_weeks
{
    my $self = shift;

    return &{$_period_attr}( $self,'weeks',@_ );
}

1;

__END__

=head1 NAME

DateTimeX::Fiscal::Fiscal5253 - Perl extension for DateTime

=head1 SYNOPSIS

 use DateTimeX::Fiscal::Fiscal5253;
  
 my $fc = DateTimeX::Fiscal::Fiscal5253->new( year => 2012 );

=head1 DESCRIPTION

This module generates calendars for a "52/53 week" fiscal year. They are
also known as "4-4-5" or "4-5-4" calendars due to the repeating week
patterns of the periods in each quarter. A 52/53 week year will B<always>
have either 52 or 53 weeks (364 or 371 days.) One of the best known of
this type is the standard Retail 4-5-4 calendar as defined by the National
Retail Federation.

You are B<strongly> advised to speak with your accounting people
(after all, the reason you are reading this is because they want reports,
right?) and show them a dump of the data for any given year and see
if it matches what they expect.

Keep in mind that when an accountant says they want data for fiscal year 2012
they are talking about an accounting year that B<ends> in 2012. An
accountant will usually think in terms of "the fiscal year ending in October,
2012." (Unless they are talking about Retail 4-5-4 years, see the section
below that deals specifically with this.)

=head1 ERROR HANDLING

All methods return C<undef> if an error occurs as well as emitting an
error message via C<carp>.

=head1 CONSTRUCTOR

=head2 new

 my $fc = DateTimeX::Fiscal::Fiscal5253->new();

The constructor accepts the following parameters:

=over 4

=item C<end_month>

set the last calendar month of the fiscal year. This should be
an integer in the range 1 .. 12 where "1" is January.
Default: 12

=item C<end_dow>

sets the last day of the week of the fiscal year. This is an
integer in the range 1 .. 7 with Monday being 1. Remember, a 52/52 week
fiscal calendar always ends on the same weekday. Default: 6 (Saturday)

=item C<end_type>

determines how to calculate the last day of the fiscal year
based on the C<end_month> and C<end_dow>. There are two legal vaules:
"Last" and "Closest". Default: "Last"

"Last" says to use the last weekday of the type specified in C<end_dow> as
the end of the fiscal year.

"Closest" says to use the weekday of the type specified that is closest
to the end of the calendar month as the last day, B<even if it is in the
following month>.

=item C<leap_period>

determines what period the 53rd week (if needed) is placed in.
This could be of importance when creating year-over-year reports.
There are two legal values: "First" and "Last". Default: "Last"

"First" says to place the extra week in period 1.

"Last" says to place the extra week in period 12.

=back

The last two parameters control what year the calendar is generated for.
B<Note:> These parameters are mutually exclusive and will throw an error
if both are present.

=over 4

=item C<year>

sets the B<fiscal year> to build for. It defaults to the correct
fiscal year for the current date or to the fiscal year containing the date
specified by C<date>.

The fiscal year value will often be different than the calendar year for
dates that are near the beginning or end of the fiscal year. For example,
Jan 3, 2015 is the last day of FYE2014 when using an C<end_type> of "closest".

B<NOTE!> In normal accounting terms, a fiscal year is named for the calendar
year it ends in. That is, for a fiscal year that ends in October, fiscal year
2005 would begin in October or November of calendar year 2004
(depending upon the setting of C<end_type>.) However, Retail 4-5-4
calendars are named for the year they B<begn> in. This means that a Retail
4-5-4 calendar for 2005 would begin in 2005 and not 2004 as an accountant
would normally think. See the discussion at the end of this documentation
about Retail 4-5-4 calendars for more information.

=item C<date>

if present, is either a string representing a date or a
L<DateTime> object. This will be used to build a calendar that contains
the given value. Again, be aware that dates that are close to the end
of a given fiscal year might have different values for the calendar year
vs the fiscal year.

If the value for C<date> is a string, it must be specified as either
"YYYY-MM-DD" or "MM/DD/YYYY" or some reason able variant of those such as
single digit days and months. Time components, if present, are discarded.
Any other format will generate a fatal error. A L<DateTime> object will be
cloned before being used to prevent unwanted changes to the original object.

=back

=head1 ACCESSORS

All accessors are B<read-only> methods that return meta-information about
parameters that were used to construct the object or the base values
represented by the object as a result of those parameters.

If you want to change any of the underlying properties that define an
object, B<create a new object!>

=head2 meta

 my $meta = $fc->meta();
 my %meta = $fc->meta();

This method will return either a hash or a reference to a hash (denpending
upon context) containing all of the available meta-information in one
structure.

 my $fc = DateTimeX::Fiscal::Fiscal5253->new( year => 2012 );
 my $fc_info = $fc->meta();
  
 print Dumper($fc_info);
 $VAR1 = {
          'end_dow' => 6,
          'leap_period' => 'last',
          'end_type' => 'last',
          'end' => '2012-12-29',
          'end_month' => 12,
          'year' => 2012,
          'start' => '2012-01-01',
          'weeks' => 52
        };

The value contained in C<$fc_info-E<gt>{year}> is the name of the fiscal year as
commonly used by accountants (as in "fye2012") and is usually the same as
the calendar year the fiscal year B<ends> in. However, it is possible for
the actual ending date to be in the B<following> calendar year when the C<end_month> is '12' (the default) and an C<end_type> of "closest" specified, Fiscal
year 2014 built as shown below demonstrates this:

 my $fc = DateTimeX::Fiscal::Fiscal5253->new(
              year => 2014,
              end_type => 'closest'
          );
 
 print Dumper($fc->meta());
 $VAR1 = {
          'end_dow' => 6,
          'leap_period' => 'last',
          'end_type' => 'closest',
          'end' => '2015-01-03',
          'end_month' => 12,
          'year' => 2014,
          'start' => '2013-12-29',
          'weeks' => 53
        };

=head2 Individual Attributes

The following are provided as a means to access the invidual items in the
above structure for those who prefer individual accessors. Remember, these
are all B<read-only>.

=over 4

=item year

 my $year = $fc->year();

=item end_month

 my $end_month = $fc->end_month();

=item end_dow

 my $end_dow = $fc->end_dow();

=item end_type

 my $end_type = $fc->end_type();

=item start

 my $start = $fc->start();

=item end

 my $end = $fc->end();

=item weeks

 my $weeks = $fc->weeks();

=item leap_period

 my $leap_period = $fc->leap_period();

=back

=head1 METHODS

=head2 has_leap_week

 my $fc = DateTimeX::Fiscal::Fiscal5253->new( year => 2006 );
 print "This is a Fiscal Leap Year" if $fc->has_leap_week;

Returns a Boolean value indicating whether or not the Fiscal Year for the
object has 53 weeks instead of the standard 52 weeks.

=head2 contains

 if ( my $pnum = $fc->contains() ) {
     print "The current date is in period $pnum\n";
 }
  
 if ( $fc->contains( date => 'today', calendar => 'Restated' ) ) {
     print 'The current day is in the Fiscal calendar';
 }
  
 if ( $fc->contains( date => '2012-01-01', calendar => 'Fiscal' ) ) {
     print '2012-01-01 is in the Fiscal calendar';
 }
  
 my $dt = DateTime->today( time_zone => 'floating' );
 if ( my $pnum = $fc->contains( date => $dt ) ) {
     print "$dt is in period $pnum\n";
 }

This method takes two named parameters, 'date' and 'calendar', and returns
the period number containing 'date' if the given date is valid for the
specified calendar. Bear in mind that some dates that are in the
Fiscal calendar might not be in a Restated or Truncated calendar.

=over 4

=item C<date>

Accepts the same formats as the contructor as well as the special
keyword 'today'. Defaults to the current date if not supplied.

=item C<calendar>

Specifies which calendar style to check against and accepts
the same values as the 'calendar' method does. The default is 'Fiscal'.

=back

=head2 calendar

 my $cal = $fc->calendar();
 my $cal = $fc->calendar( style => 'Normal' );
 my $rcal = $fc->calendar( style = 'Restated' );
 
 my @cal = $fc->calendar()
 ...

Returns either an array or a reference to an array (depending upon
context) that contains an entry with meta data in the first element
($cal->[0]) and period (month) data in the folling twelve entries. This
allows for a natural access cycle using C<for ( 1 .. 12 )> in many cases.

It accepts a single parameter, C<style>, which must be 'Fiscal',
'Restated' or 'Truncated' (defaults to 'Fiscal'.)

The value 'Fiscal' will build a calendar with the full number of weeks
without regard to whether there are 52 or 53 weeks in the year.

The value 'Restated' says to ignore the first week in a 53 week year and
create a calendar with only 52 weeks. This allows for more accurate
year-over-year comparisons involving a year that would otherwise have
53 weeks.

The value 'Truncated' says to ignore the last week in a 53 week year and
create a calendar with only 52 weeks. This may allow for more accurate
year-over-year comparisons involving a year that would otherwise have
53 weeks.

B<Note!> The method will return a 'Fiscal' calendar if either 'Restated'
or 'Truncated' is requested for a normal 52 week year since there is
no difference in those cases.

The meta information in the first element ($cal[0]) contains the following
information about how the calendar (B<not the object!>) is configured:

 print Dumper($rcal->[0]);
 $VAR1 = {
          'end_dow' => 6,
          'leap_period' => 'last',
          'style' => 'restated',
          'end_type' => 'closest',
          'end' => '2013-02-02',
          'end_month' => 1,
          'year' => 2013,
          'start' => '2012-02-05',
          'weeks' => 52
        };

B<Note!> The meta data in the calendar structure B<will> be different from that
returned by the 'meta' method if either 'Restated' or 'Truncated' is
requested for a 53 week year! Always use the data from the 'meta' method to
see how the object itself was created.

Each period element will have information about the period's start and end
dates, number of weeks, and the nominal name of the month as well as the
period number.

 print Dumper($cal=>[1]);
 $VAR1 = {
          'period' => 1,
          'month' => 'February',
          'end' => '2012-03-03',
          'weeks' => 4,
          'start' => '2012-02-05'
        };

=head2 period

 my %pdata = $fc->period( period => 5, calendar => 'Restated' );
 my $pdata = $fc->period( period => 1, calendar => 'Fiscal' );

Read-only method that returns a hash or a reference to a hash depending
upon context that contains all of the data for the requested period in
the specified calendar type.

=over 4

=item C<period>

Must be a number in the range 1 - 12. If not given, the current date will
used if it exists in the requested calendar and return the period data
containing it.

=item C<calendar>

Specifies what calendar style to retrieve the period information from. Legal
values are the same as the C<style> parameter for the 'calendar' method.
Default is 'Fiscal'.

=back

The returned data is as follows:

 print Dumper($pdata);
 $VAR1 = { 
          'period' => 1,
          'month' => 'February',
          'start' => '2012-02-04',
          'weeks' => 4,
          'end' => '2012-03-02'
        };

B<Note!> It is an error condition to supply a value of C<undef> for 'period'.
Consider what can happen if one is tempted to write code such as this:

 my $pinfo = $fc->period( period => $fc->contains( date => $somedate ) );

This could produce unexpected results if C<$somedate> does not exist in the
calendar. Without this restriction, the 'period' method would attempt
to use the current date, which may or may not exist in the object, and would
almost certainly be different than what was desired.

The following methods are provided for those who want to access the individual
components of the period structure without dealing with a hash. They return
a scalar value and accept the same parameters as C<period> does. C<undef>
will be returned if an error occurs.

=over 4

=item period_month

 my $pmonth = $fc->period_month( period => 3, calendar => 'Fiscal' );

=item period_start

 my $pstart = $fc->period_start( period => 5 );

=item period_end

 my $pend = $fc->period_end( calendar => 'Fiscal' );

=item period_weeks

 my $pweeks = $fc->period_weeks( period => 2, calendar => 'Restated' );

=back

There is no method to return the period number component because presumably
you already know that. Use the "contains" method to get the period number
for the current date if applicable. (Besides, C<$fc-E<gt>period_period> is just
plain ugly!)

=head1 Retail 4-5-4 calendars

A Retail 4-5-4 calendar (as described by the National Retail Federation here:
L<http://www.nrf.com/modules.php?name=Pages&sp_id=392>) is an example of a
Fiscal 52/53 week year that starts on the Sunday closest to Jan 31 of
the specified year.

In other words, to create a Retail 4-5-4 calendar for 2012, you will create
a Fiscal5253 object that ends in 2013 on the Saturday closest to Jan 31.

B<Note!> Fiscal years are named for the year they end in, Retail 4-5-4
years are named for the year they B<begin> in!

 # Create a Retail 4-5-4 calendar for 2012
 my $r2012 = DateTimeX::Fiscal::Fiscal5253->new(
     year => 2013,          # This will be the ending year for the calendar
     end_month => 1,        # End in January
     end_dow => 6,          # on the Saturday
     end_type => 'closest', # closest to the end of the month
     leap_period => 'last'  # and any leap week in the last period
 );

You can verify that this is correct by viewing the calendars available at
the NRF website: L<http://www.nrf.com/4-5-4Calendar>

The reporting date can be determined by adding 5 days to the end of any
given period. Using L<DateTime> makes this trivial:

 # Get the reporting date for period 5 for the object created above
 my ($y,$m,$d) = split(/\-/,$r2012->period_end( period => 5 ));
 my $report_date = DateTime->new(
     year => $y,
     month => $m,
     day => $d
 )->add( days => 5 )->ymd;

=head1 DEPENDENCIES

L<DateTime>, L<Carp>

=head1 TO DO

Add better error reporting via a class variable/method instead of
using L<Carp> messages.

Add methods to work with fiscal week numbers.

Allow the C<leap_period> parameter to 'new' to accept a number in the
range 1 .. 12 besides 'first' and 'last' to specify explicitly which
period to place any leap week in.

Anything else that users of this module deem desirable.

=head1 SEE ALSO

L<DateTime> to get ideas about how to work with an object suppiled to
the constructor as the C<date> parameter.

Do a Google (or comparable) search to learn more about Fiscal Years and
the 52/53 week. This is a fairly arcane subject that usually is of interest
only to accountants and those of us who must provide reports to them.

Of particular interest will be how a Retail 4-5-4 calendar differs in
definition from an accounting 4-4-5 fiscal year.

=head1 CREDITS

This module, like any other in the L<DateTime> family, could not exist
without the work and dedication of Dave Rolsky.

=head1 SUPPORT

Support is provided by the author. Please report bugs or make feature
requests to the email address below.

=head1 AUTHOR

Jim Bacon, E<lt>jim@nortx.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Jim Bacon

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
