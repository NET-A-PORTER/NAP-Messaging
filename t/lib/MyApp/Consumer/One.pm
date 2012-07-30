package MyApp::Consumer::One;
use NAP::policy 'class';
extends 'NAP::Messaging::Base::Consumer';

sub routes {
    return {
        my_input_queue => {
            my_message_type => {
                spec => {
                    type => '//rec',
                    required => { count => '//int'},
                },
                code => \&my_consume_method,
            },
        },
    }
}

sub my_consume_method {
    my ($self,$message,$headers) = @_;

    $self->log->info("sending reply");

    $self->amq->transform_and_send('MyApp::Producer::Foo',{
        count => $message->{count} + 1,
    });

    warn "testing logtrapper"
        if $self->_c->config->{logtrapper}{enable};

    $self->log->info("sent");

    return;
}
