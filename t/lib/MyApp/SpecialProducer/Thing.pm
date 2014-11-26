package MyApp::SpecialProducer::Thing;
use NAP::policy 'class','tt';
with 'NAP::Messaging::Role::Producer';

has '+type' => ( default => 'special' );

sub transform {
    my ($self,$header) = @_;

    return ($header, {});
}
