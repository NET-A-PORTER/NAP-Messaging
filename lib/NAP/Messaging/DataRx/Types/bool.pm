package NAP::Messaging::DataRx::Types::bool;

use strict;
use warnings;

use parent 'Data::Rx::CoreType';
use NAP::Messaging::DataRx::Compat;

# ABSTRACT: A custom bool type that accepts '0' or '1' as boolean values.

=head1 SYNOPSIS

 { type => '/nap/bool' }

This will accept '0' or '1' as boolean values.

=cut

sub type_uri {
  sprintf 'http://net-a-porter.com/%s', $_[0]->subname
}

sub subname { 'bool' };

sub assert_valid {
    my ( $self, $value ) = @_;
    return 1 if $value =~ m{^\d$} and ($value == 0 or $value == 1);
    $self->fail({
        error   => ['bool'],
        message => 'bool must be 0 or 1',
        value   => $value,
    });
}

1;

=begin Pod::Coverage

type_uri
subname
assert_valid

=end Pod::Coverage
