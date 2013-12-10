#!perl
use NAP::policy 'test','tt';
use Test::Fatal;
use Test::NAP::Messaging;

package MyProducer {
    use NAP::policy 'class';
    with 'NAP::Messaging::Role::Producer';

    has '+destination' => ( default => 'logical_dest' );
    has '+type' => ( default => 'logical_type' );
    has '+set_at_type' => ( default => 0 );

    sub transform {
        my ($self,$header) = @_;

        my $reply_to = $self->map_destination('reply_to');

        return ($header, {rt=>$reply_to});
    }
};

my $out;
cmp_deeply(
    $out=[MyProducer->new->transform()],
    [superhashof({
        destination => '/queue/logical_dest',
        type => 'logical_type',
    }),{rt=>'/queue/reply_to'}],
    'no mapping') or note p $out;

cmp_deeply(
    $out=[MyProducer->new({
        destination => '/queue/ld2',
    })->transform()],
    [superhashof({
        destination => '/queue/ld2',
        type => 'logical_type',
    }),{rt=>'/queue/reply_to'}],
    'no mapping, configured destination') or note p $out;

cmp_deeply(
    $out=[MyProducer->new({
        routes_map => { logical_dest => 'actual_dest' },
    })->transform()],
    [superhashof({
        destination => '/queue/actual_dest',
        type => 'logical_type',
    }),{rt=>'/queue/reply_to'}],
    'mapped destination 1-1') or note p $out;

cmp_deeply(
    $out=[MyProducer->new({
        routes_map => { logical_dest => [qw(ad1 ad2)] },
    })->transform()],
    bag(
        superhashof({
            destination => '/queue/ad1',
            type => 'logical_type',
        }),{rt=>'/queue/reply_to'},
        superhashof({
            destination => '/queue/ad2',
            type => 'logical_type',
        }),{rt=>'/queue/reply_to'},
    ),
    'mapped destination 1-2') or note p $out;

cmp_deeply(
    $out=[MyProducer->new({
        routes_map => { logical_dest => { actual_dest => {
            logical_type => 'actual_type',
        }}}
    })->transform()],
    [superhashof({
        destination => '/queue/actual_dest',
        type => 'actual_type',
    }),{rt=>'/queue/reply_to'}],
    'mapped destination 1-1, type 1-1') or note p $out;

cmp_deeply(
    $out=[MyProducer->new({
        routes_map => { logical_dest => { actual_dest => {
            logical_type => [qw(at1 at2)],
        }}}
    })->transform()],
    bag(
        superhashof({
            destination => '/queue/actual_dest',
            type => 'at1',
        }),{rt=>'/queue/reply_to'},
        superhashof({
            destination => '/queue/actual_dest',
            type => 'at2',
        }),{rt=>'/queue/reply_to'},
    ),
    'mapped destination 1-1, type 1-2') or note p $out;

cmp_deeply(
    $out=[MyProducer->new({
        routes_map => { logical_dest => {
            ad1 => {
                logical_type => [qw(at1 at2)],
            },
            ad2 => {
                logical_type => [qw(at3 at4)],
            },
        }}
    })->transform()],
    bag(
        superhashof({
            destination => '/queue/ad1',
            type => 'at1',
        }),{rt=>'/queue/reply_to'},
        superhashof({
            destination => '/queue/ad1',
            type => 'at2',
        }),{rt=>'/queue/reply_to'},
        superhashof({
            destination => '/queue/ad2',
            type => 'at3',
        }),{rt=>'/queue/reply_to'},
        superhashof({
            destination => '/queue/ad2',
            type => 'at4',
        }),{rt=>'/queue/reply_to'},
    ),
    'mapped destination 1-2, type 1-2') or note p $out;

cmp_deeply(
    $out=[MyProducer->new({
        routes_map => { reply_to => 'actual_reply_to' },
    })->transform()],
    [superhashof({
        destination => '/queue/logical_dest',
        type => 'logical_type',
    }),{rt=>'/queue/actual_reply_to'}],
    'mapped reply-to 1-1') or note p $out;

my $e = exception {
    MyProducer->new({
        routes_map => { reply_to => [qw(rt1 rt2)] },
    })->transform();
};

cmp_deeply($e,
           all(
               isa('NAP::Messaging::Exception::BadConfig'),
               methods(
                   detail => re(qr{\breply_to maps to multiple\b}),
                   config_snippet => { reply_to => ignore() },
               ),
           ),
           'bad reply-to mapping');

done_testing();
