# Declare our package
package POE::Component::Server::SimpleHTTP::Request;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Initialize our version
our $VERSION = '1.01';

# Set our stuff to HTTP::Request
use base qw( HTTP::Request );

# Sets the Connection
sub _Connection {
	# Get ourself!
	my $self = shift;

	# Get the connection object
	my $conn = shift;

	# Set it!
	$self->{'CONNECTION'} = $conn;

	# All done!
	return 1;
}

# Gets the connection object
sub connection {
	# Get ourself!
	my $self = shift;

	# Return the object
	return $self->{'CONNECTION'};
}

# End of module
1;

__END__
=head1 NAME

POE::Component::Server::SimpleHTTP::Request - Emulates a HTTP::Request object, used for SimpleHTTP

=head1 SYNOPSIS

	use POE::Component::Server::SimpleHTTP::Request;
	my $response = POE::Component::Server::SimpleHTTP::Request->new( );

	# Print connection port
	print $response->connection->Remote_Port;

=head1 CHANGES

=head2 1.01

	Initial Revision

=head1 DESCRIPTION

	This module is used as a drop-in replacement, because we need to store the connection information.

=head2 EXPORT

Nothing.

=head1 SEE ALSO

	L<POE::Component::Server::SimpleHTTP>
	L<POE::Component::Server::SimpleHTTP::Connection>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut