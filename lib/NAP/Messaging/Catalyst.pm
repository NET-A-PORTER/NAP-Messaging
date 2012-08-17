package NAP::Messaging::Catalyst;
use NAP::policy 'class';

# ABSTRACT: base application class for AMQ consumers

=head1 SYNOPSIS

  package MyApp;
  use NAP::Policy 'class';
  extends 'NAP::Messaging::Catalyst';

  __PACKAGE__->setup();

=head1 DESCRIPTION

This is a Catalyst application base class, from which you derive your
own. The derivation does not really need to do anything, it's mostly
to set the application name to your own namespace.

=head2 What does this do?

=over 4

=item *

if C<$ENV{CATALYST_DEBUG}> or C<$ENV{TEST_VERBOSE}> are set, Catalyst
is set up in debug mode

=item *

a few plugins are loaded by default: C<ConfigLoader>, C<ErrorCatcher>,
C<StackTrace>, and L<CatalystX::ComponentsFromConfig::ModelPlugin>.

=cut

use Catalyst;
use Log::Log4perl::Catalyst;

__PACKAGE__->arguments([
    ( $ENV{CATALYST_DEBUG} || $ENV{TEST_VERBOSE} ? '-Debug' : () ),
    qw(
          ConfigLoader
          ErrorCatcher
          StackTrace
          +NAP::Messaging::Catalyst::LogTrapper
          +CatalystX::ComponentsFromConfig::ModelPlugin
  )
]);

=item *

the C<_application> method is redefined to get a cached version of the
application name discovered during setup: this is only needed in some
rather convoluted inheritance systems where each application base
class brings in its own components

=cut

{
my $app_class_name;
sub _set_class_name { $app_class_name = shift }
sub _application { $app_class_name }
}

before setup_components => sub {
    my ($class) = @_;

    $class->_set_class_name();
    push @{$class->config->{setup_components}->{search_extra}},
        'NAP::Messaging::Catalyst::Controller','::Consumer';
};

=item *

at the end of setup, anything logged (usually only debug statements)
are flushed (usually to C<STDOUT>), and a L<Log::Log4perl::Catalyst>
instance replaces the default logger:

    $class->log(Log::Log4perl::Catalyst->new(
        $class->config->{log4perl},
        %{$class->config->{log4perlopts} // {}},
    ));

=cut

before setup_finalize => sub {
    my ($class) = @_;

    return unless $class->config->{log4perl};

    $class->log->_flush() if $class->log->can('_flush');
    $class->log(Log::Log4perl::Catalyst->new(
        $class->config->{log4perl},
        %{$class->config->{log4perlopts} // {}},
    ));
};

=back

=method C<jms_destinations>

returns the destinations that this application can consume from; this
works reliably if you use L<NAP::Messaging::Base::Consumer> to define
your consumers, and get them loaded by setting C<<
config->{setup_components}{search_extra} >> to include you consumer
namespace.

=cut

sub jms_destinations {
    my ($class) = @_;

    # we extract namespaces & destinations from the application controllers
    my @namespaces = map { $class->controller($_)->action_namespace }
        $class->controllers;
    my @destinations = map { '/'.$_ }
        grep { m{^(queue|topic)}x } @namespaces;
    return @destinations;
}

# __PACKAGE__->setup(); do this in your own subclass
