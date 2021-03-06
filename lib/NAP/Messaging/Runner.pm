package NAP::Messaging::Runner;
use NAP::policy 'class','tt';
use Plack::Handler::Stomp;
use FindBin::libs;
use MooseX::Types::LoadableClass qw/ LoadableClass /;
use Moose::Util::TypeConstraints 'duck_type';
use Net::Stomp::MooseHelpers::Types 'ServerConfigList';

# ABSTRACT: helper class to start applications

=head1 SYNOPSIS

  #!perl
  use NAP::policy;
  use NAP::Messaging::Runner;
  NAP::Messaging::Runner->new('MyApp')->run;

=head1 DESCRIPTION

This class wraps the repetitive steps needed to start a L<NAP::Messaging>-based consumer application:

=for :list
* load the application class
* extract C<STOMP> configs
* instantiate L<Plack::Handler::Stomp>
* set up subscriptions and logging
* run the application via the handler

=attr C<appclass>

The application class to use. Required. The application will be loaded
if it hasn't been already. You can also pass an application I<object>
here, as long as it implements the C<log>, C<jms_destinations>, and
C<config> methods.

=cut

has appclass => (
    is => 'ro',
    isa => LoadableClass | duck_type([qw(log jms_destinations config)]),
    required => 1,
    coerce => 1,
);

=method C<BUILDARGS>

You can pass a single string to C<new>, which will be interpreted as
the L</appclass>.

=cut

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;

    if ( @_ == 1 && !ref $_[0] ) {
        return $class->$orig({ appclass => $_[0] });
    }
    else {
        return $class->$orig(@_);
    }
};

=attr C<handler>

Instance of L<Plack::Handler::Stomp> (or similar classes),
lazy-built. It will use the application's C<MessageQueue> model to get
connection information, C<jms_destination> to get the subscriptions
(via L</subscriptions>), and will delegate the handler's logging to
the application's logger. Additionally, in the C<Stomp> section of the
application's configuration, you can specify parameters to be passed
to C<Plack::Handler::Stomp>'s constructor. You can also specify which
class to use instead of C<Plack::Handler::Stomp> (as
C<handler_class>), and traits / roles to apply to it
(C<handler_traits>). For example:

  <Stomp>
   handler_traits [ Net::Stomp::MooseHelpers::TraceStomp ]
   trace_basedir t/tmp/amq_dump_dir
   trace 1
   <connect_headers>
    client-id myapp
   </connect_headers>
   <subscribe_headers>
    activemq.exclusive false
    activemq.prefetchSize 1
   </subscribe_headers>
  </Stomp>

B<NOTE>: C<client-id> is a bad idea if you plan to run multiple
parallel instances off the same configuration (e.g. via
L<NAP::Messaging::MultiRunner>): the broker will refuse all
connections after the first.

The broker to connect to will be taken from the application's
C<Model::MessageQueue>, unless you specify a C<< <servers> >> value in
the C<Stomp> section, like this:

 <Stomp>
  <servers>
   hostname broker.local
   port     61613
  </servers>
  <servers>
   hostname broker.failover
   port     61613
  </servers>
 </Stomp>

=cut

has handler => (
    is => 'ro',
    lazy_build => 1,
    isa => duck_type(['new','run']),
);

sub _build_handler {
    my ($self) = @_;
    my $appclass = $self->appclass;
    my $config = $appclass->config->{Stomp} // {};

    # we will connect to the same servers as the application uses to send
    # messages, unless we get specific ones in the Stomp config
    my $servers = $config->{servers}
        ? to_ServerConfigList($config->{servers})
        : $appclass->model('MessageQueue')->servers;

    my @subscriptions = $self->subscriptions;

    my $handler_class = delete $config->{handler_class}
        // 'Plack::Handler::Stomp';
    my $handler_traits = delete $config->{handler_traits};

    if ($handler_traits && @$handler_traits) {
        # just in case someone gets confused with other
        # class-specification conventions
        s{^\+}{} for @$handler_traits;

        my $meta = $self->meta->create_anon_class(
            superclasses => [ $handler_class ],
            roles        => $handler_traits,
            cache        => 1,
        );
        $handler_class = $meta->name;
    }

    # now we can build the handler
    my $handler = $handler_class->new({
        %{ $appclass->config->{Stomp} // {} },
        servers => $servers,
        subscriptions => \@subscriptions,
        logger => $appclass->log,
    });

    return $handler;
}

=method C<subscriptions>

Calls the L</appclass>'s C<jms_destinations> method, then converts
that list into the format required by L<Plack::Handler::Stomp>'s
C<subscriptions> attribute (i.e. C<< ( { destination => '/queue/some'
}, { destination => '/queue/other' } ) >>)

=cut

sub subscriptions {
    my ($self) = @_;

    return map {; {
        destination => $_,
    } } $self->appclass->jms_destinations;
}

=method C<run>

Gets the application's entry point, and passes it to the L</handler>'s
C<run> method.

=cut

sub run {
    my ($self) = @_;
    my $appclass = $self->appclass;

    # and have it run our application
    if ($appclass->can('psgi_app')) {
        $self->handler->run($appclass->psgi_app);
    }
    else {
        $appclass->setup_engine('PSGI');
        $self->handler->run( sub { $appclass->run(@_) } );
    }
}
