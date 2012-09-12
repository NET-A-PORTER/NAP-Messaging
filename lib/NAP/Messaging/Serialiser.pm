package NAP::Messaging::Serialiser;
use NAP::policy 'class';
use MooseX::ClassAttribute;
use Moose::Util::TypeConstraints;
use JSON::XS;

# ABSTRACT: global (de)serialiser container class

=head1 SYNOPSIS

  my $json = NAP::Messaging::Serialiser->serialise($data_structure);

  my $data_structure = NAP::Messaging::Serialiser->deserialise($json);

=head1 DESCRIPTION

We don't want to instantiate dozens of serialiser objects all over the
place. So this class instantiate the only one we need.

=attr C<serialiser>

The serialiser object. It's expected to implement the C<encode> and
C<decode> methods, just like L<JSON>.

=method C<serialise>

Delegated to C<< ->serialiser->encode >>

=method C<deserialise>

Delegated to C<< ->serialiser->decode >>

=cut

class_has serialiser => (
    is => 'rw',
    isa => duck_type([qw(encode decode)]),
    builder => 'build_serialiser',
    handles => {
        serialise => 'encode',
        deserialise => 'decode',
    }
);

=method C<build_serialiser>

Instantiate a L<JSON::XS> object with utf8 conversion and delegation
to C<TO_JSON> for blessed refs.

=cut

sub build_serialiser {
    JSON::XS->new->utf8->allow_blessed->convert_blessed;
}
