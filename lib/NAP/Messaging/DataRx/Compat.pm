package NAP::Messaging::DataRx::Compat {
use NAP::policy;
use Sub::Install;

# ABSTRACT: compatibility shim to ease upgrade to Data::Rx 0.2

=head1 SYNOPSIS

  package My::Rx::type;
  use parent 'Data::Rx::CoreType';
  use NAP::Messaging::DataRx::Compat;

  sub guts_from_arg { ... } # like Moose's 'BUILDARGS'

  sub assert_valid { ... } # like our 'validate'

  1;

=head1 DESCRIPTION

Our patched version of L<Data::Rx> 0.007 implemented structured error
reporting. The official version 0.2 implements that as well, but with
a slightly different API.

This module allows you to write type classes that will work under both
versions.

=head1 OTHER CONSIDERATIONS

Our version throws L<Data::Rx::Failure>, the official version throws
L<Data::Rx::FailureSet>. See L<NAP::Messaging::Exception::Validation>
for a way to handle both.

=head1 FUTURE

After we've migrated out of our patched version, we should remove the
use of this module, and start inheriting from
L<Data::Rx::CommonType::EasyNew> istead of L<Data::Rx::CoreType>.

=head1 Details

On import, we do nothing if the caller is inheriting from a recent
enough version of L<Data::Rx>. Otherwise, we  inject
C<NAP::Messaging::DataRx::CompatBase> as first base class, to provide
the other helper methods.

=cut

sub import {
    my $caller = caller;

    my $caller_isa = do {
        no strict 'refs';
        \@{"${caller}::ISA"};
    };

    # are we inheriting from a recent Data::Rx? do nothing
    return if $caller_isa->[0]->can('guts_from_arg');

    unshift @$caller_isa, 'NAP::Messaging::DataRx::CompatBase';
}

}

=head2 C<NAP::Messaging::DataRx::CompatBase>

Helper base class, don't use directly.

=cut

package NAP::Messaging::DataRx::CompatBase {
    use NAP::policy;
    use Carp ();

=head3 C<validate>

Our alias for C<assert_valid>

=head2  C<new_checker>

Constructor, that will call C<guts_from_arg> to get the actual
internals of the object to bless.

=head3 C<guts_from_arg>

Default "buildargs"-like, croaks if passed arguments.

=head3 C<perform_subchecks>

Poor fake implementation, just delegates to C<_subcheck>

=cut

    sub validate { my $self = shift; $self->assert_valid(@_) }

    sub new_checker {
        my ($class, $arg, $rx) = @_;

        my $guts = $class->guts_from_arg($arg, $rx);

        $guts->{rx}   = $rx;

        bless $guts => $class;
    }

    sub guts_from_arg {
        my ($class, $arg, $rx) = @_;

        Carp::croak "$class does not take check arguments" if %$arg;

        return {};
    }

    sub perform_subchecks {
        my ($self, $subchecks) = @_;

        $self->_subcheck(@$_) for @$subchecks;
    }
}
