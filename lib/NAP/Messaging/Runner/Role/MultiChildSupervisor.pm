package NAP::Messaging::Runner::Role::MultiChildSupervisor;
use NAP::policy 'tt';
use MooseX::Role::Parameterized;
use NAP::Messaging::Runner::ChildSupervisor;

# ABSTRACT: parameterised role to get supervisor attributes

=head1 SYNOPSIS

  package MyRunner;
  use NAP::policy 'class','tt';
  with 'NAP::Messaging::Role::MultChildSupervisor' => {
    name => 'munger',
  };

  sub run_munger_child { ... }

  # see NAP::DocIntegrator::Runner for the rest

=head1 DESCRIPTION

Consuming this role gives you an attribute just like C<consumers> in
L<NAP::Messaging::MultiRunner>.

=head1 PARAMETERS

=head2 C<name>

Base name. The attribute will be called C<"${name}s">. Instances will
be retrived by calling the C<"${name}_children_wanted"> method. In
each child, the method C<"run_${name}_child"> will be called

=cut

parameter name => (
    isa => 'Str',
    required => 1,
);

=head2 C<instances_config_key>

The name of the key under the the C<runner> config that specifies how
many instances to run. Default C<${name}_instances>.

=cut

parameter instances_config_key => (
    isa => 'Str',
);

=head2 C<default_instance_count>

The default number of instances to run if not specified in the config.
Default C<1>.

=cut

parameter default_instance_count => (
    isa => 'Int',
    default => 1,
);

role {
    my $p=shift;
    my $name = $p->name;
    my $run_method = "run_${name}_child";
    my $attr_name = "${name}s";
    my $instances_method = "${name}_children_wanted";
    my $instances_config_key = $p->instances_config_key // "${name}_instances";
    my $default_instance_count = $p->default_instance_count;

=head1 REQUIRED METHODS

=head2 C<appclass>

A L<Catalyst> / L<NAP::Messaging> application class, used to access
the configuration and the logger.

=cut

    requires 'appclass';

=head2 C<run_${name}_child>

The method is called to run the application after forking the child.

=cut

    requires $run_method;

has $attr_name => (
    is => 'ro',
    isa => 'ArrayRef[NAP::Messaging::Runner::ChildSupervisor]',
    lazy_build => 1,
);

method "_build_${attr_name}" => sub {
    my ($self) = @_;

    return [ map {
        # lexicalise so we can close over it in the 'code' argument
        my $instance_config = $_;
        NAP::Messaging::Runner::ChildSupervisor->new({
            name => $instance_config->{name},
            trapped_signals => \@NAP::Messaging::MultiRunner::trapped_signals,
            logger => $self->appclass->log,
            instances => $instance_config->{instances},
            code => sub {
                if (my $setup = $instance_config->{setup}) {
                    my $setup_method = $setup->{method};
                    $self->$setup_method($setup->{args});
                }
                $self->$run_method;
            },
        });
    } @{$self->$instances_method} ];
};

=head2 C<remove_child>

=head2 C<fork_all>

=head2 C<stop_children>

Hooked to delegate to the L<NAP::Messaging:Runner::ChildSupervisor>
objects in the C<${name}s> attribute.

=cut

for my $method (qw(remove_child fork_all stop_children)) {
    requires $method;
    after $method => sub {
         my $self = shift;
         # During global destruction, the supervisors may already have been reaped
         $_->$method(@_) for grep { defined } @{$self->$attr_name};
    };
}

method $instances_method => sub {
    my ($self, $config) = @_;
    my $instances = ($config // $self->appclass->config)->{runner}{$instances_config_key}
       // $default_instance_count;

    # plain scalar? turn it into a single instance
    $instances = { instances => $instances } unless ref($instances);

    # not an array ref? wrap it in one
    $instances = [ $instances ] unless ref($instances) eq 'ARRAY';

    # make sure we get the defaul number of children child per
    # partition and add a name, if not specified
    my $partition_number = 0;
    return [ map {
        $partition_number++;
        +{
            instances => $default_instance_count,
            name => $name . (@{$instances} > 1 ? " (partition $partition_number)" : ''),
            %{$_},
        };
    } @{$instances} ];
};


=head2 C<extract_child_config>

Wrapped to add the values from C<${name}_children_wanted>.

=cut

requires 'extract_child_config';
around extract_child_config => sub {
    my ($orig, $class) = (shift, shift);

    return [
        @{$class->$orig(@_)},
        @{$class->$instances_method(@_)},
    ];
};

};

