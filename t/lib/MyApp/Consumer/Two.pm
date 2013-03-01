package MyApp::Consumer::Two;
use NAP::policy 'class';
extends 'NAP::Messaging::Base::Consumer';
use NAP::Messaging::Utils 'object_message','ignore_extra_fields';

sub routes {
    return {
        my_input_queue => {
            string_message => {
                spec => {
                    type => '//rec',
                    required => { value => '//str'},
                },
                code => object_message(\&munge_the_string),
            },
            padded_message => {
                spec => ignore_extra_fields({
                    type => '//rec',
                    required => { value => '//str' },
                }),
                code => object_message(\&munge_the_string),
            },
        },
    }
}

sub munge_the_string {
    my ($self,$message,$headers) = @_;

    die 'testing death'
        if $message->value eq 'die';

    $self->log->info("sending string reply");

    $self->amq->transform_and_send('MyApp::Producer::Bar',{
        string => $message->value . "\x{1F603}",
    });

    $self->log->info("string sent");

    return;
}
