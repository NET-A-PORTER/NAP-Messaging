package Plack;
use NAP::policy 'tt';
use NAP::Messaging::Runner;
use Net::Stomp::Producer;
use Data::Printer;
use Scalar::Util 'blessed';

$ENV{CATALYST_CONFIG}='t/lib/myapp.really.conf';
my $runner = NAP::Messaging::Runner->new('MyApp');
$runner->handler->one_shot(1);
$runner->handler->connect();
$runner->handler->subscribe();

my $env;
my $app = $runner->appclass->psgi_app;
my $wrapped_app = sub { $env=$_[0]; $app->(@_) };

sub request {
    MyApp->model('MessageQueue')->send(
        @_
    );
    try {
        $env=undef;
        $runner->handler->frame_loop($wrapped_app)
            until $env;
    }
    catch {
        if (blessed($_) && $_->isa('Plack::Handler::Stomp::Exceptions::OneShot')) {
        }
        else { die $_ }
    };
}

sub test_it {
    request( # invalid payload
        'queue/the_actual_queue_name',
        { type => 'my_message_type' },
        { bad => 'input' },
    );
    request( # exception
        'queue/stringy',
        { type => 'string_message' },
        { value => 'die' },
    );
    request( # 404
        'queue/the_actual_queue_name',
        { type => 'whatever' },
        { },
    );

    request(
        '/queue/the_actual_queue_name',
        { type => 'my_message_type' },
        { count => 13 },
    );
    request(
        '/queue/stringy',
        { type => 'string_message' },
        { value => "\x{1F662}" },
    );
    request(
        '/queue/deep',
        { type => 'my_message_type' },
        { count => 27 },
    );
}
