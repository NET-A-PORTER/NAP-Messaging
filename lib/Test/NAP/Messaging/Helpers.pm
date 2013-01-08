package Test::NAP::Messaging::Helpers {
use NAP::policy 'exporter';
use Sub::Exporter -setup => {
    exports => [ 'napdate', 'atleast' ],
    groups => [ default => [ 'napdate', 'atleast' ] ],
};

# ABSTRACT: helpers to test messages

=func C<napdate>

  napdate($datetime_obj)

Returns a C<Test::Deep> comparator that will compare a L<DateTime>
object (or its stringification in a message, see
L<NAP::Messaging::Role::Producer>) against the passed-id object.

=cut

sub napdate { Test::NAP::Messaging::Helpers::DateCompare->new(@_) }


=func C<atleast>

  atleast($number)

Returns a C<Test::Deep> comparator that will compare a number to see
if it is C<< >= >> the parameter.

=cut

sub atleast { Test::NAP::Messaging::Helpers::AtLeast->new(@_) }

}

package Test::NAP::Messaging::Helpers::DateCompare {
    use strict;use warnings;
    use Scalar::Util qw( blessed );
    use parent 'Test::Deep::Cmp';

    sub _format_datetime {
        my ($self,$date) = @_;
        if (blessed($date) && $date->can('strftime')) {
            return $date->strftime("%Y-%m-%dT%H:%M:%S.%3N%z");
        }
        return "$date";
    }

    sub init {
        my ($self,$date) = @_;
        $self->{date} = $date;
        $self->{strdate} = $self->_format_datetime($date);
    }

    sub descend {
        my ($self,$got) = @_;

        $self->data->{got} = $self->_format_datetime($got);

        return $self->data->{got} eq $self->{strdate};
    }

    sub diag_message {
        my ($self,$where) = @_;
        return "Comparing NAP dates on $where";
    }

    sub render_stack1 {
        my ($self,$stack) = @_;
        my $date=$self->{date};
        return "(${stack}->format(...) eq ${date}->format(...))"
    }
    sub renderExp {
        my ($self) = @_;
        return "$self->{date}";
    }
}

package Test::NAP::Messaging::Helpers::AtLeast {
    use strict;use warnings;
    use parent 'Test::Deep::Cmp';

    sub init {
        my ($self,$min) = @_;
        $self->{min} = $min+0;
    }

    sub descend {
        my ($self,$got) = @_;

        $self->data->{got_string} = $got;
        { no warnings 'numeric';
          $got += 0; }
        $self->data->{got} = $got;

        return $self->data->{got} >= $self->{min};
    }

    sub diag_message {
        my ($self,$where) = @_;
        return "Comparing $where an a number against a lower limit";
    }

    sub renderGot {
        my ($self,$val) = @_;

        my $got_string = $self->data->{got_string};
        if ("$val" ne "$got_string") {
            $got_string = $self->SUPER::renderGot($got_string);
            return "$val ($got_string)"
        }
        else {
            return $val;
        }
    }
    sub renderExp {
        my ($self) = @_;
        return "$self->{min}";
    }
}
