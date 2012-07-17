package NAP::Messaging::DataRx::Types::datetime;

use strict;
use warnings;

use DateTime::Format::ISO8601;
use Data::Rx::CoreType;
use parent 'Data::Rx::CoreType';

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

# TODO: If we want we could add a restriction on the range here.

=for example

sub new_checker {
  my ($class, $arg, $rx) = @_;

  my $self = bless { } => $class;
  return $self;

  Carp::croak("unknown arguments to new")
    unless Data::Rx::Util->_x_subset_keys_y($arg, { range => 1, value => 1});

  return $self;
}
=cut

sub validate {
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
validate

=end Pod::Coverage
