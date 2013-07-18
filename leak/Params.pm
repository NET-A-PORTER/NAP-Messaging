package Params;
use NAP::policy 'tt';
use MooseX::Params::Validate;
use MooseX::Types::Structured qw/Map Dict slurpy/;
use MooseX::Types::Moose qw/HashRef Bool ArrayRef Str/;

package Params::Types {
    use NAP::policy 'tt';

    use MooseX::Types::Moose qw{ Int Str };

    use MooseX::Types -declare => [ qw{
                                          ProductId ChannelId BusinessId VariantId FreeStock YmalSubId YmalRank ListAction
                                  } ];

    subtype ProductId,
        as Int,
            where {
                $_ >= 1 && $_ <= 0x7FFFFFFF
            },
                message { 'Invalid product ID' };

    subtype ChannelId,
        as Int,
            where {
                $_ >= 1 && $_ <= 0x7FFFFFFF
            },
                message { 'Invalid channel ID' };

    subtype BusinessId,
        as Int,
            where {
                $_ >= 1 && $_ <= 0x7FFFFFFF
            },
                message { 'Invalid business ID' };

    subtype VariantId,
        as Int,
            where {
                $_ >= 1 && $_ <= 0x7FFFFFFF
            },
                message { 'Invalid variant ID' };

    subtype FreeStock,
        as Int,
            where {
                $_ >= -0x80000000 && $_ <= 0x7FFFFFFF
            },
                message { 'Invalid free stock value' };

    subtype YmalSubId,
        as Int,
            where {
                $_ >= 1 && $_ <= 0x7FFFFFFF
            },
                message { 'Invalid YMAL sub-ID' };

    subtype YmalRank,
        as Int,
            where {
                $_ >= 1 && $_ <= 0x7FFFFFFF
            },
                message { 'Invalid YMAL rank' };

    subtype ListAction,
        as Str,
            where {
                $_ eq 'create' || $_ eq 'delete'
            },
                message { 'Invalid action - must be "create" or "delete"' };
};

BEGIN { Params::Types->import(qw/ListAction ChannelId ProductId/) }
use Data::Printer;

sub test_it {
    my $out_hash={};
    my @args=(
        (bless {}, __PACKAGE__),
        sale_flags_by_pid => $out_hash,
        list_action       => {
            action => 'create',
            type => 'custom_list',
            pids => [ 1..5000 ],
            etc => 'foo',
        },
    );

    my ($self, $sale_flags_by_pid, $list_action) = validated_list(
        \@args,
        sale_flags_by_pid => { isa => Map[ProductId, Bool]  },
        list_action       => { isa => Dict[
                action => ListAction, # create or delete
                type   => Str,
                pids   => ArrayRef,
                slurpy HashRef # Allow any other keys
                # (Don't put anything after "slurpy")
            ]
        },
    );
    #p $list_action;
}
