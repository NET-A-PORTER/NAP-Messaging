#!perl
use NAP::policy 'test';
use NAP::Messaging::Utils 'object_message','ignore_extra_fields','ignore_extra_fields_deep';

subtest 'object_message' => sub {
    # the 'undef' would be the $self of the coderef
    # note that we also don't return it :)
    my ($m,$h) = object_message(sub{@_[1,2]})->(undef,{body=>1},{header=>2});
    is($m->body,1,'body value passed');
    is($h->header,2,'header value passed');
};

sub rest_schema_ok {
    my ($h,$name) = @_;
    $name//='';

    cmp_deeply($h,
               superhashof({ rest => '//any' }),
               "$name is ignoring extra fields");
}
sub rest_schema_not {
    my ($h,$name) = @_;
    $name//='';

    ok(!exists $h->{rest},
       "$name is not ignoring extra fields");
}

subtest 'ignore_extra_fields' => sub {
    rest_schema_not(ignore_extra_fields({
        type => '//arr'
    }),'array');

    rest_schema_ok(ignore_extra_fields({
        type => '//rec'
    }),'record');

    rest_schema_ok(ignore_extra_fields({
        type => '/nap/rec'
    }),'NAP record');

    my $x=ignore_extra_fields({
        type => '//rec',
        required => {
            foo => {
                type => '//rec',
            },
        },
    });
    rest_schema_ok($x,'top-level record');
    rest_schema_not($x->{required}{foo},'nested record');
};

subtest 'ignore_extra_fields_deep' => sub {
    rest_schema_not(ignore_extra_fields_deep({
        type => '//arr'
    }),'array');

    rest_schema_ok(ignore_extra_fields_deep({
        type => '//rec'
    }),'record');

    rest_schema_ok(ignore_extra_fields_deep({
        type => '/nap/rec'
    }),'NAP record');

    my $x=ignore_extra_fields_deep({
        type => '//rec',
        required => {
            foo => {
                type => '//rec',
            },
        },
    });
    rest_schema_ok($x,'top-level record');
    rest_schema_ok($x->{required}{foo},'nested record');
};

done_testing();
