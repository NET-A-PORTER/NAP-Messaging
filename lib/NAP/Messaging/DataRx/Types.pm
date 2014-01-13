package NAP::Messaging::DataRx::Types;
use NAP::policy 'tt';
use parent 'Data::Rx::TypeBundle';
use Module::Runtime 'require_module';

# ABSTRACT: specialized NAP Data::Rx types

=head1 DESCRIPTION

This type bundle loads a few new types, under the prefix C</nap/>

See L<NAP::DocIntegrator::DataRx::Types::bool>,
L<NAP::DocIntegrator::DataRx::Types::datetime> and
L<NAP::DocIntegrator::DataRx::Types::sku> for the definition of those
types.

=begin Pod::Coverage

prefix_pairs
type_plugins

=end Pod::Coverage

=cut

sub prefix_pairs {
    return (
        nap => 'http://net-a-porter.com/',
    )
}

sub type_plugins {
    return qw(
                 NAP::Messaging::DataRx::Types::bool
                 NAP::Messaging::DataRx::Types::datetime
                 NAP::Messaging::DataRx::Types::sku
    )
}

require_module($_) for type_plugins();
