package NAP::Messaging::Role::Component;
use NAP::policy 'role','tt';
use Catalyst::Utils ();

# ABSTRACT: instance-based Catalyst Component

=head1 DESCRIPTION

Consuming this role makes your class into an instance-based Catalyst
component, and gives you a read-only accessor called C<_c> to get at
the application object.

=cut

has _c => (
    is => 'ro',
    required => 1,
);

=method C<COMPONENT>

Called by Catalyst, calls C<new> passing the Catalyst application as
the C<_c> argument, in addition to any additional arguments that may
come from the configuration.

=cut

sub COMPONENT {
    my ($class,$c) = @_;

    my $arguments = ( ref( $_[-1] ) eq 'HASH' ) ? $_[-1] : {};
    $arguments->{_c} //= $c;

    return $class->new($arguments);
}

=method C<BUILDARGS>

Copied from L<Catalyst::Component>, merges the configuration (see
L</config>) with the passed arguments.

=cut

sub BUILDARGS {
    my $class = shift;
    my $args = {};

    if (@_ == 1) {
        $args = $_[0] if ref($_[0]) eq 'HASH';
    } elsif (@_ == 2) { # is it ($app, $args) or foo => 'bar' ?
        if (blessed($_[0])) {
            $args = $_[1] if ref($_[1]) eq 'HASH';
        } elsif (Class::MOP::is_class_loaded($_[0]) &&
                $_[0]->isa('Catalyst') && ref($_[1]) eq 'HASH') {
            $args = $_[1];
        } else {
            $args = +{ @_ };
        }
    } elsif (@_ % 2 == 0) {
        $args = +{ @_ };
    }

    return Catalyst::Utils::merge_hashes($class->config($args->{_c}),$args);
}

=method C<config>

Retrieves the configuration for this component from the general
Catalyst configuration. This is much less flexible and robust than the
actual Catalyst implementation. In particular, you can I<not> set
static configuration in your classes.

This uses L</short_class_name> to get the key to use in the global
configuration.

=cut

sub config {
    my ($self,$c) = @_;

    $c //= $self->_c;

    my $short_class_name = $self->short_class_name($c);

    return $c->config->{$short_class_name} // {};
}

=method C<short_class_name>

  my $short = MyApp->component('Foo::Bar')->short_class_name;
  # $short eq 'Bar';

Called on an I<instance>, takes the instance class name, strips the
application name from the start of it, then strips the next "namespace
component". Returns what's left.

If the class name does not begin with the application name, returns
the class name intact.

=cut

sub short_class_name {
    my ($self,$app_class_name) = @_;

    my $class_name = ref($self) || $self;
    $app_class_name //= ref($self->_c) || $self->_c;

    my ($short_class_name) = (
        $class_name =~ m{^\Q$app_class_name\E::((?:\w+)::.*)\z}
    );

    $short_class_name //= $class_name;

    return $short_class_name;
}
