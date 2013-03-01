package Test::NAP::Messaging;
use NAP::policy 'class';
use Net::Stomp::MooseHelpers::ReadTrace 1.002;
use Net::Stomp::Frame;
use Plack::Handler::Stomp;
use Test::Builder;
use Test::Deep qw(cmp_details deep_diag ignore);
use NAP::Messaging::Serialiser;
use Data::Printer;
use HTTP::Response;
use HTTP::Message::PSGI;
use Net::Stomp::Producer;
use Net::Stomp::MooseHelpers::TraceOnly 1.002;
use Path::Class;
use MooseX::Types::Path::Class;
use Test::NAP::Messaging::Helpers 'add_random_fields';

# ABSTRACT: testing helper for NAP::Messaging applications

=head1 SYNOPSIS

   use NAP::policy 'test';
   use Test::NAP::Messaging;

   my ($tester,$app_entry_point) = Test::NAP::Messaging->new_with_app({
     app_class => 'MyApp',
     config_file => 't/lib/myapp.conf',
   });

   $tester->clear_destination;

   my $response = $tester->request(
       $app_entry_point,
       'queue/the_actual_queue_name',
       { count => 13 },
       { type => 'my_message_type' },
   );
   ok($response->is_success);

   $tester->assert_messages({
       destination => 'queue/the_actual_destination',
       filter_header => superhashof({type => 'my_response'}),
       assert_count => 1,
       assert_body => superhashof({ value => 14 }),
   });

   done_testing();

In C<t/lib/myapp.conf> make sure you have:

   <Model::MessageQueue>
    base_class NAP::Messaging::Catalyst::MessageQueueAdaptor
    <args>
     trace_basedir t/tmp/amq_dump_dir
    </args>
    traits [ +Net::Stomp::MooseHelpers::TraceOnly ]
   </Model::MessageQueue>

=head1 DESCRIPTION

This library helps in testing applications based on L<NAP::Messaging>.

=attr C<trace_basedir>

The directory into which frames will be stored, and from which they
will be read. L</frame_reader> uses this, and so does L</producer>.

=cut

has trace_basedir => (
    is => 'ro',
    isa => 'Path::Class::Dir',
    required => 1,
    coerce => 1,
);

=attr C<config_hash>

The application configuration. Used to set up L</trace_basedir> if not
passed in, and to pass the configuration to the L</producer>'s
transformers.

=cut

has config_hash => (
    is => 'ro',
    isa => 'HashRef',
    required => 0,
    default => sub { { } },
);

around BUILDARGS => sub {
    my $orig=shift;my $self=shift;
    my $args = $self->$orig(@_);

    if ($args->{config_hash} && !$args->{trace_basedir}) {
        $args->{trace_basedir} = $args->{config_hash}
            {'Model::MessageQueue'}{args}{trace_basedir};
    }

    return $args;
};

=attr C<frame_reader>

An instance of L<Net::Stomp::MooseHelpers::ReadTrace>, using
L</trace_basedir>.

=method C<clear_destination>

Delegated to L</frame_reader>, see
L<Net::Stomp::MooseHelpers::ReadTrace/clear_destination>.

=cut

has frame_reader => (
    is => 'ro',
    isa => 'Net::Stomp::MooseHelpers::ReadTrace',
    lazy_build => 1,
    handles => [ 'clear_destination' ],
);

sub _build_frame_reader {
    return Net::Stomp::MooseHelpers::ReadTrace->new({
        trace_basedir => $_[0]->trace_basedir,
    });
}

=attr C<producer>

An instance of L<Net::Stomp::Producer> with the
L<Net::Stomp::MooseHelpers::TraceOnly> role applied to it. Uses
L</trace_basedir>. You may want to set C<<
->producer->transformer_args >> to something other than the default
(but see also L</new_with_app>).

=method C<send>

Delegated to L</producer>, see L<Net::Stomp::Producer/send>.

=method C<transform_and_send>

Delegated to L</producer>, see L<Net::Stomp::Producer/transform_and_send>.

=cut

has producer => (
    is => 'ro',
    isa => 'Net::Stomp::Producer',
    lazy_build => 1,
    handles => [qw(send transform transform_and_send)],
);

sub _build_producer {
    my ($self) = @_;
    my $prod = Net::Stomp::Producer->new({
        serializer => $self->serializer,
        default_headers => {
            'content-type' => 'json',
            persistent => 'true',
        },
        transformer_args => {
            _global_config => $self->config_hash,
        },
    });
    Net::Stomp::MooseHelpers::TraceOnly->meta->apply($prod);
    $prod->trace_basedir($self->trace_basedir);
    return $prod;
}

=attr C<serializer>

Coderef, defaults to L<NAP::Messaging::Serialiser/serialise>. Used to
serialise messages sent via the L</producer>.

=cut

has serializer => (
    isa => 'CodeRef',
    is => 'ro',
    default => sub { sub { NAP::Messaging::Serialiser->serialise($_[0]) } }
);

=attr C<deserializer>

Coderef, defaults to L<NAP::Messaging::Serialiser/deserialise>. Used
to deserialise messages read via the L</frame_reader>.

=cut

has deserializer => (
    isa => 'CodeRef',
    is => 'ro',
    default => sub { sub { NAP::Messaging::Serialiser->deserialise($_[0]) } }
);

has _tester => (
    is => 'ro',
    lazy_build => 1,
);

sub _build__tester {
    return Test::Builder->new;
}

=method C<messages>

  my @messages = $tester->messages($destination);

Returns all the useful frames (the C<SEND> and C<MESSAGE> ones) from
the given destination (or all destination, if you don't specify), on
the order they were produced.

=cut

sub messages {
    my $self=shift;

    my @ret;

    for my $frame ($self->frame_reader->sorted_frames(@_)) {
        # ignore ACK, CONNECT, SUBSCRIBE and the like
        next unless $frame->command eq 'SEND'
            || $frame->command eq 'MESSAGE';
        push @ret,$frame;
    }

    return @ret;
}

=method C<assert_messages>

  $tester->assert_messages({
    destination => $topic_or_queue,
    filter_header => $cmq_deeply_argument,
    filter_body => $cmq_deeply_argument,
    assert_header => $cmq_deeply_argument,
    assert_body => $cmq_deeply_argument,
    assert_count => $cmq_deeply_argument,
  },$test_comment);

Scans through the L</messages> on the given destination, filtering
their headers and bodies against the C<filter_header> and
C<filter_body> parameters.

Each message that passed the filter must pass the comparison against
C<assert_header> and C<assert_body>. and the number of messages
filtered must pass the comparison against C<assert_count>.

All comparisons are done with L<Test::Deep/cmp_deeply> (yes, including
C<assert_count>), so you probably want to use C<superhashof> most
times. They're also all done in a subtest; the subtest gets the
C<$test_comment>.

An example of usage: you want to test that 1 or 2 messages of type
C<something> were sent to C</queue/foo>, and that the C<id> value in
the (deserialised) body is C<'the_right_one'>; you'd write:

  $tester->assert_messages({
    destination => '/queue/foo',
    filter_header => superhashof({type=>'something'}),
    assert_body => superhashof({id=>'the_right_one'}),
    assert_count => any(1,2),
  });

This will ignore messages of different types, or sent to different
destinations; it will fail if any of the non-ignored messages have a
different C<id>, or if there are less than 1 or more than 2.

=cut

sub assert_messages {
    my ($self,$opts,$comment) = @_;

    my $destination = $opts->{destination};
    my $filter_header = $opts->{filter_header} // ignore();
    my $filter_body = $opts->{filter_body} // ignore();
    my $assert_header = $opts->{assert_header} // ignore();
    my $assert_body = $opts->{assert_body} // ignore();
    my $assert_count = $opts->{assert_count} // 1;

    my $filtered = 0;
    my $test = $self->_tester;

    my @stacks;

    my $failed=0;

    $test->subtest($comment, sub {
        for my $frame ($self->messages($destination ? $destination : ())) {
            push @stacks,{};

            my ($fh,$fstackh) = cmp_details($frame->headers,$filter_header);
            $stacks[-1]->{filter_header}=$fstackh;
            next unless $fh;

            my $body = $self->deserializer->($frame->body);

            my ($fb,$fstackb) = cmp_details($body,$filter_body);
            $stacks[-1]->{filter_body}=$fstackb;
            next unless $fb;

            ++$filtered;

            my ($ah,$astackh) = cmp_details($frame->headers,$assert_header);
            unless ($test->ok(
                $ah,
                "message number $filtered headers assert"
            )) {
                ++$failed;
                my $diag = deep_diag($astackh);
                $test->diag($diag);
                $test->diag(p $frame->headers);
                $stacks[-1]->{assert_header}=$astackh;
            }

            my ($ab,$astackb) = cmp_details($body,$assert_body);
            unless ($test->ok(
                $ab,
                "message number $filtered body assert"
            )) {
                ++$failed;
                my $diag = deep_diag($astackb);
                $test->diag($diag);
                $test->diag(p $body);
                $stacks[-1]->{assert_body}=$astackb;
            }
        }

        my ($ac,$astackc) = cmp_details($filtered,$assert_count);
        unless ($test->ok($ac,"count assert")) {
            ++$failed;
            my $diag = deep_diag($astackc);
            $test->diag($diag);
            $test->diag("\n".$self->_full_stack_dump(\@stacks));
        }
    });

    return !$failed;
}

sub _full_stack_dump {
    my ($self,$stacks) = @_;

    my $ret='';my $count=0;

    for my $s (@$stacks) {
        $ret .= "Message $count:\n";
        for my $f (qw(filter_header filter_body assert_header assert_body)) {
            $ret .= my $pre = "$f: ";
            if (!$s->{$f}) {
                $ret .= "not checked\n";
            }
            elsif ($s->{$f}->length) {
                my $pad = ' ' x length($pre);
                my $diag = deep_diag($s->{$f});
                $diag =~ s{(?!\A)^}{$pad}mg;
                $ret .= $diag;
            }
            else {
                $ret .= "matched\n";
            }
        }
        $ret .= "\n";++$count;
    }

    return $ret;
}

=method C<request>

  my $response = $tester->request(
     $psgi_app,
     $destination,
     $message, $headers );

Prepares a request based on the given message, and runs it through the
C<$psgi_app>. Returns a L<HTTP::Response> built from whatever the
application returned.

This does I<not> trap exceptions, but your PSGI application should not
die anyway.

=cut

sub request {
    my ($self,$app,$destination,$message,$headers) = @_;

    if (ref($message)) {
        $message = $self->serializer->($message);
    }

    my $frame = Net::Stomp::Frame->new({
        command => 'SEND',
        headers => {
            destination => $destination,
            'content-type' => 'json',
            %{ $headers // {} },
        },
        body => $message,
    });

    # this may be wrong. path maps may well be needed.
    my $phs = Plack::Handler::Stomp->new();
    my $psgi_env = $phs->build_psgi_env($frame);
    my $psgi_response = $app->($psgi_env);

    my $http_response = HTTP::Response->from_psgi($psgi_response);

    return $http_response;
}

=method C<request_with_extra_fields>

  my $response = $tester->request_with_extra_fields(
     $psgi_app,
     $destination,
     $message, $headers );

If the C<$message> is not a hashref, this method just calls
L</request>. If the C<$message> is a hashref, C</request> is called
with the message modified through
L<Test::NAP::Messaging::Helpers/add_random_fields>.

=cut

sub request_with_extra_fields {
    my ($self,$app,$destination,$message,$headers) = @_;

    if (ref($message) eq 'HASH') {
        ($headers,$message) = add_random_fields($headers,$message);
    }
    $self->request($app,$destination,$message,$headers);
}

=head1 CONSTRUCTORS

In decreasing order of usefulness:

=head2 C<new_with_app>

  my ($tester, $psgi_app) = Test::NAP::Messaging->new_with_app({
    app_class => 'MyApp',
    config_file => 't/myapp.conf',
  });

Loads and sets up your application, using the given configuration
file. If the resulting application does not apply the
L<Net::Stomp::MooseHelpers::TraceOnly> role to its
C<::Model::MessageQueue>, or does not set the C<trace_basedir>, this
method will croak. You do not want to test while talking to a real
broker.

The logger is reset to a simple L<Catalyst::Log> instance, with
automatic flushing, and C<info> and C<debug> messages turned off
(unless you're running under C<$ENV{TEST_VERBOSE}>). This way,
whatever logging configuration you use normally won't affect your
tests.

Then, an instance of C<Test::NAP::Messaging> is created, using the
passing the application's C<< ->config >> as C<config_hash> (see
below).

Finally, this instance and the PSGI entry point for the application
are returned.

=head2 C<new> with C<config_hash>

  my $tester = Test::NAP::Messaging->new({
    config_hash => My::App->config,
  });

This will use the passed-in configuration to set C<trace_basedir>
(from C<< config_hash->{'Model::MessageQueue'}{args}{trace_basedir}
>>) and the C<< ->producer->transformer_args->{_global_config} >>. The
latter ensumers that C<routes_map> in your producers / transformers
will be honoured.

=head2 C<new>

  my $tester = Test::NAP::Messaging->new({
    trace_basedir => '/tmp/foo',
  });

The normal L<Moose> constructor.

In this case, any C<routes_map> in your producers / transformers will
not be used, since the C<$tester> object knows nothing about the
configuration.

=cut

sub new_with_app {
    my ($class,$args) = @_;

    my $app_class = $args->{app_class}
        or croak "new_with_app needs an application";
    my $config_file = $args->{config_file}
        or croak "new_with_app needs a configuration file";

    {
        local $ENV{CATALYST_CONFIG} = file($config_file)->absolute
            ->resolve->stringify;

        Class::MOP::load_class($app_class);
        $app_class->import();
    }

    $app_class->log(Test::NAP::Messaging::CatalystLog->new);
    $app_class->log->disable(qw/info debug/)
        unless $ENV{TEST_VERBOSE};

    croak "the MessageQueue model of $app_class does not have the 'trace_basedir' method, can't test (did you apply the Net::Stomp::MooseHelpers::TraceOnly role?)"
        unless $app_class->model('MessageQueue')->can('trace_basedir');

    my $dump_dir=$app_class->model('MessageQueue')->trace_basedir;

    croak "the MessageQueue model of $app_class is not configured with a 'trace_basedir', can't test"
        unless $dump_dir;

    dir($dump_dir)->mkpath;

    my $tester = $class->new({
        trace_basedir => $dump_dir,
        config_hash => $app_class->config,
    });

    my $entry_point;
    if ($app_class->can('psgi_app')) {
        $entry_point = $app_class->psgi_app();
    }
    else {
        $app_class->setup_engine('PSGI');
        $entry_point = sub { $app_class->run(@_) };
    }

    return ($tester,$entry_point);
}

package Test::NAP::Messaging::CatalystLog {
    use NAP::policy 'class';
    extends 'Catalyst::Log';
    after _log => sub {
        $_[0]->_flush();
    };
    __PACKAGE__->meta->make_immutable(inline_constructor=>0);
}
