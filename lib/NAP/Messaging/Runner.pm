package NAP::Messaging::Runner;
use NAP::policy 'class';
use Plack::Handler::Stomp;
use FindBin::libs;
use MooseX::Types::LoadableClass qw/ LoadableClass /;

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
if it hasn't been already.

=cut

has appclass => (
    is => 'ro',
    isa => LoadableClass,
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

Instance of L<Plack::Handler::Stomp>, lazy-built. It will use the
application's C<MessageQueue> model to get connection information,
C<jms_destination> to get the subscriptions, and will delegate the
handler's logging to the application's logger. Additional parameters
to be passed to C<Plack::Handler::Stomp>'s constructor can be
specified in the C<Stomp> section of the application's configuration.

=cut

has handler => (
    is => 'ro',
    lazy_build => 1,
);

sub _build_handler {
    my ($self) = @_;
    my $appclass = $self->appclass;

    # we will connect to the same servers as the application uses to send
    # messages
    my $servers = $appclass->model('MessageQueue')
        ->servers;

    my @subscriptions = map {; {
        destination => $_,
    } } $appclass->jms_destinations;

    # now we can build the handler
    my $handler = Plack::Handler::Stomp->new({
        %{ $appclass->config->{Stomp} // {} },
        servers => $servers,
        subscriptions => \@subscriptions,
        logger => $appclass->log,
    });

    return $handler;
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
