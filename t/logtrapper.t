#!perl
use NAP::policy 'test','tt';
use Test::NAP::Messaging;

my $logfile = '/tmp/myapp.log';

unlink $logfile;

my ($tester,$app_entry_point) = Test::NAP::Messaging->new_with_app({
    app_class => 'MyApp',
    config_file => 't/lib/myapp.trapper.conf',
});

my $response = $tester->request(
    $app_entry_point,
    'queue/the_actual_queue_name',
    { count => 13 },
    { type => 'my_message_type' },
);
ok($response->is_success,'message was consumed');

my $log_contents = do { open my $fh,'<',$logfile;local $/;<$fh> };
like($log_contents,
     qr{\bt/lib/MyApp/Consumer/One\.pm \d+ NAP\.Messaging\.Catalyst\.LogTrapper\.Tied - \[LogTrapper\] testing logtrapper at [^\n]*?\bt/lib/MyApp/Consumer/One\.pm line \d+},
     'stderr trapped');

done_testing();
