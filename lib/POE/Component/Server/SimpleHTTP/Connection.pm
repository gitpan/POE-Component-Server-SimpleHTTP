# Declare our package
package POE::Component::Server::SimpleHTTP::Connection;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Initialize our version
our $VERSION = '1.04';

# Get some things we need
use Socket qw( inet_ntoa unpack_sockaddr_in );

# Creates a new instance!
sub new {
	# Get rid of the class
	my $class = shift;

	# Create the hash
	my $self = {
		# Did the socket die?
		'DIED'	=>	0,
	};

	# Get the stuff
	my $socket = shift;

	# Figure out everything!
	eval {
		( $self->{'remote_port'}, $self->{'remote_addr'} ) = unpack_sockaddr_in( getpeername( $socket ) );
		$self->{'remote_ip'} = inet_ntoa( $self->{'remote_addr'} );

		( $self->{'local_port'}, $self->{'local_addr'} ) = unpack_sockaddr_in( getsockname( $socket ) );
		$self->{'local_ip'} = inet_ntoa( $self->{'local_addr'} );
	};

	# Check for errors!
	if ( $@ ) {
		# Just ignore this socket and return nothing!
		return undef;
	}

	# Bless ourself!
	bless( $self, 'POE::Component::Server::SimpleHTTP::Connection' );

	# All done!
	return $self;
}

# Gets the remote_ip
sub remote_ip {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'remote_ip'};
}

# Gets the remote_port
sub remote_port {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'remote_port'};
}

# Gets the remote_addr
sub remote_addr {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'remote_addr'};
}

# Gets the local_addr
sub local_addr {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'local_addr'};
}

# Gets the local_ip
sub local_ip {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'local_ip'};
}

# Gets the local_port
sub local_port {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'local_port'};
}

# Boolean accessor to check if the socket is dead
sub dead {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'DIED'};
}

# End of module
1;

__END__
=head1 NAME

POE::Component::Server::SimpleHTTP::Connection - Stores connection information for SimpleHTTP

=head1 SYNOPSIS

	use POE::Component::Server::SimpleHTTP::Connection;
	my $connection = POE::Component::Server::SimpleHTTP::Connection->new( $socket );

	# Print some stuff
	print $connection->remote_port;

=head1 CHANGES

=head2 1.04

	Added the dead accessor

=head2 1.03

	Updated POD
	Added local_ip + local_port accessors

=head2 1.02

	Got rid of funky CaPs in methods

=head2 1.01

	Initial Revision

=head1 DESCRIPTION

	This module simply holds some information from a SimpleHTTP connection.

=head2 METHODS

	my $connection = POE::Component::Server::SimpleHTTP::Connection->new( $socket );

	$connection->remote_ip();	# Returns remote ip in dotted quad format ( 1.1.1.1 )
	$connection->remote_port();	# Returns remote port
	$connection->remote_addr();	# Returns true remote address, consult the L<Socket> POD
	$connection->local_addr();	# Returns true local address, same as above
	$connection->local_ip();	# Returns local ip in dotted quad format ( 1.1.1.1 )
	$connection->local_port();	# Returns local port
	$connection->dead();		# Returns a boolean value whether the socket is closed or not

=head2 EXPORT

Nothing.

=head1 SEE ALSO

	L<POE::Component::Server::SimpleHTTP>

	L<POE::Component::Server::SimpleHTTP::Response>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2004 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut