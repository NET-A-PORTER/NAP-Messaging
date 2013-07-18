package MyApp::Producer::Bar;
use NAP::policy 'class','tt';
with 'NAP::Messaging::Role::Producer';

sub message_spec { +{
    type => '//rec',
    required => { response => '//str'}
} }

has '+destination' => ( default => 'my_destination' );
has '+type' => ( default => 'string_response' );

sub transform {
    my ($self,$header,$arg) = @_;

    return ($header, { response => $arg->{string} });
}
