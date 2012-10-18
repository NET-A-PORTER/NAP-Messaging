package MyApp::Producer::Foo;
use NAP::policy 'class';
with 'NAP::Messaging::Role::Producer';

sub message_spec { +{
    type => '//rec',
    required => { value => '//int'}
} }

has '+type' => ( default => 'my_response' );

sub transform {
    my ($self,$header,$arg) = @_;

    return ($header, { value => $arg->{count} });
}
