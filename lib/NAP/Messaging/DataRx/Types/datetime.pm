package NAP::Messaging::DataRx::Types::datetime;

use strict;
use warnings;

use DateTime::Format::ISO8601;
use parent 'Data::Rx::CoreType';
use NAP::Messaging::DataRx::Compat;

# ABSTRACT: A custom datetime type for Data::Rx

=head1 SYNOPSIS

 { type => '/nap/datetime' }

And this will validate any ISO8601 date time string parsable by
L<DateTime::Format::ISO8601>.

=cut

sub type_uri {
  sprintf 'http://net-a-porter.com/%s', $_[0]->subname
}

sub subname { 'datetime' };

sub assert_valid {
    my ($self, $value) = @_;

    eval {
        DateTime::Format::ISO8601->parse_datetime( "$value" );
    };

    if (my $error = $@) {
        chomp $error;
        $self->fail({
            error => ['datetime'],
            message => $error,
            value => $value,
        });
    }
    return 1;
}

1;

=begin Pod::Coverage

type_uri
subname
assert_valid

=end Pod::Coverage
