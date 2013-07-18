#!/usr/bin/env perl
use NAP::policy 'tt';
use Devel::Peek;
use lib 'leak','lib','t/lib';
use Module::Runtime 'require_module';

{
# pre-alloc some memory
my %report;my @diffs=(100)x100;
sub measure {
    my (%args) = @_;
    my $code = $args{code} // sub {};
    my $cleanup = $args{cleanup} // sub {};
    my $loops = $args{loops} // [1];

    $code->();

    mstats_fillhash(%report);
    $diffs[0]=$report{total}-$report{totfree};

    keys @$loops;
    while (my ($i,$count) = each @$loops) {
        say "$i: looping $count times";

        $code->() for 1..$count;
        $cleanup->();

        mstats_fillhash(%report);
        $diffs[$i+1]=$report{total}-$report{totfree};

        say " diff: ",$diffs[$i+1]-$diffs[$i];
        say '';
    }

    for my $i (1..@$loops) {
        printf "% 3d (% 5d times): % 10d % 10.1f\n",
            $i,$loops->[$i-1],
            $diffs[$i]-$diffs[$i-1],
            ($diffs[$i]-$diffs[$i-1])/$loops->[$i-1];
    }
}
}

my $module = $ARGV[0];
require_module($module);

measure
    code => sub { $module->test_it },
    loops => [ 10, 10, 20, 40, 80, 160, 320, 640, 1280 ];
