package NAP::Messaging::Exception::Validation;
use NAP::policy 'class','overloads','tt';
use Moose::Util::TypeConstraints;
use Data::Dump 'pp';
use overload
    '""' => \&to_string,
    fallback => 1;

# ABSTRACT: wrapper for L<Data::Rx> failure exceptions

=head1 SYNOPSIS

    try {
        $schema->validate($data);
    }
    catch {
	when (match_instance_of('Data::Rx::Failure')) {
            my $exc = NAP::Messaging::Exception::Validation->new({
                source_class => __PACKAGE__,
                data => $data,
                error => $_,
            });
            warn $exc->rx_failure_reason;
        }
        default {
            warn $_;
        }
    };

=head1 DESCRIPTION

Given a L<Data::Rx::Failure> object, extract the significant parts
from it, and present them as a readable string.

=cut

subtype 'NAP::Messaging::Exception::Validation::SourceClass', as 'Str';

coerce 'NAP::Messaging::Exception::Validation::SourceClass', from 'Object',
    via { ref(shift) };

=attr C<source_class>

Used when stringifying, to explain where the error comes from. If
assigned a reference, will coerce it to its class name.

=cut

has source_class => (
    isa => 'NAP::Messaging::Exception::Validation::SourceClass',
    is => 'ro',
    coerce => 1,
);

=attr C<data>

The data that failed to validate

=cut

has data => (
    is => 'ro',
);

=attr C<error>

The exception we're wrapping.

=cut

has error => (
    is => 'ro',
);

around BUILDARGS => sub {
    my ($orig,$class,@args)=@_;

    if (@args==3) {
        return $class->$orig({
            source_class => $args[0],
            data => $args[1],
            error => $args[2],
        });
    }
    else {
        return $class->$orig(@args);
    }
};

=method C<to_string>

Returns a long error message, with dumps of L</data> and L</error>.

Used also for the overloaded stringification.

=cut

sub to_string {
    my ($self)=@_;

    my $err = $self->error;
    my $err_msg = ref($err) ? pp($err) : "$err";

    return sprintf "%s validation failed\n %s\nData was:\n %s",
        $self->source_class,
        $err_msg,
        pp($self->data);
}

=method C<is_rx_failure>

Tests whether L</error> is an instance of L<Data::Rx::Failure>.

=cut

sub is_rx_failure {
    my ($self) = @_;

    local $@; # don't clobber the caller's $@, and use eval to avoid
              # checking 'blessed' or similar
    return eval { $self->error->isa('Data::Rx::Failure') }
}

=method C<rx_failure_reason>

Returns a compact explanation of the failure, by only showing the
element that failed, and what it should have been.

=cut

sub rx_failure_reason {
    my ($self) = @_;

    return unless $self->is_rx_failure();

    my $err = $self->error;
    my $path = (join ', ',@{$err->path_to_value}) || 'top level';
    my $message = $err->struct->[0]{message};
    my $value = $err->struct->[0]{value};

    return sprintf 'Validation error at %s: %s; value was %s',
        $path,$message,pp($value);
}
