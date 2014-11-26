package Imported::Producer::Something;
use NAP::policy 'class','tt';
with 'NAP::Messaging::Role::Producer';

has '+type' => ( default => 'something' );

sub transform {
    my ($self,$header) = @_;

    return ($header, {});
}
