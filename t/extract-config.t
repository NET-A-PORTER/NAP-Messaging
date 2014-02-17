#!perl
use NAP::policy 'test','tt';
use Config::Any;
use NAP::Messaging::MultiRunner;

my $config_file = 't/lib/myapp.conf';
my $config = Config::Any->load_files({
    use_ext => 1,
    flatten_to_hash => 1,
    files => [ $config_file ],
})->{$config_file}
    or die "Can't load $config_file";

# test aggregation or forkprove might already have loaded it,
# so only test that it doesn't get loaded if it's not already
my $already_loaded = exists($INC{'MyApp.pm'});

cmp_deeply(
    NAP::Messaging::MultiRunner->extract_child_config($config),
    [
        superhashof({
            name => 'consumer (deep)',
            instances => 2,
            setup => {
                method => 'limit_destinations_to',
                args => '/queue/deep',
            },
        }),
        superhashof({
            name => 'consumer (other)',
            instances => 3,
            setup => {
                method => 'limit_destinations_to',
                args => ['/queue/stringy', '/queue/the_actual_queue_name' ],
            },
        })
    ],
    'Child config extracted',
);

ok(!exists($INC{'MyApp.pm'}), "App not loaded")
    unless $already_loaded;
done_testing;
