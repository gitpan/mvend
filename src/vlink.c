/* vlink.c:  runs as a cgi program and passes request to Vend server
			 starts MiniVend or Vend server if not running

   $Id: vlink.c,v 1.1 1996/05/03 18:43:28 mike Exp mike $

   Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>

   Modified by Mike Heins <mikeh@iac.net>

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
*/

#include "config.h"
#include <errno.h>
#include <fcntl.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#ifndef ENVIRON_DECLARED
extern char** environ;
#endif

/* The following symbols should be defined:
 * 
 * LINK_FILE
 * Location of the unix socket file for communication with the server.
 * This must be in the local filesystem, not an NFS mounted one.
 *
 * LINK_TIMEOUT
 * Define timeout in seconds to wait for the server to start listening
 * on the socket.
 *
 * PERL
 * Location of perl on your system
 *
 * VEND
 * Location of minivend on your system
 * 
 * NET_START
 * Set to "-notify" (the default) to send mail to the
 * admin address that the server is not running
 * Set to "-netstart" to automatically start the
 * server if it is not running
 * A value of "-test" will send an innocuous message 
 * that we are "doing development"
 *
 */

#define LINK_FILE "/usr/local/lib/minivend/etc/socket"
#define LINK_TIMEOUT 20
#define PERL     "/usr/bin/perl"
#define VEND     "/usr/local/lib/minivend/minivend.pl"
#define NET_START   "-netstart"


/* CGI output to the server is on stdout, fd 1.
 */
#define CGIOUT 1

/* Define as x to enable verbose debugging output.
 */
#define DEBUG(x)

#ifdef sun
#define USE_PUTENV
#ifndef SVR4
#define USE_PERROR
#endif
#endif

#ifdef sgi
#define USE_PUTENV
#endif


#ifdef USE_PERROR
#define ERRMSG perror
#else
#define ERRMSG strerror
#endif



/* Return this message to the browser when the server is not running.
 */
void server_not_running()
{
  char opt;

  opt = 0;

  printf("Content-type: text/html\r\n\r\n");
  printf("<H3>We're sorry, the MiniVend server was not running...\r\n");

  if (!strncmp("-not", NET_START, 4)) opt = 1;
  if (!strncmp("-net", NET_START, 4)) opt = 2;

  switch (opt) {
      case 1: 
	  	printf("We notified the administrator.</H3>\r\n");
		break;
      case 2: 
      	printf("We started it for you. Click reload to begin.</H3>\r\n");
		break;
	  default:
      	printf("We are probably doing development!</H3>\r\n");
		exit(1);
  }
  fflush(stdout);
  return;
}

/* Return this message to the browser when a system error occurs.
 * Should we log to a file?  Email to admin?
 */
static void die(e, msg)
     int e;
     char* msg;
{
  printf("Content-type: text/plain\r\n\r\n");
  printf("We are sorry, but the cgi-bin server is unavailable due to a\r\n");
  printf("system error.\r\n\r\n");
  printf("%s: %s (%d)\r\n", msg, ERRMSG(e), e);
  exit(1);
}


/* Read the entity from stdin if present.
 */
static int entity_len = 0;
static char* entity_buf = 0;

static void
get_entity()
{
  int len;
  char* cl;
  int nr;

  entity_len = 0;
  cl = getenv("CONTENT_LENGTH");
  if (cl != 0)
    entity_len = atoi(cl);

  if (entity_len == 0) {
    entity_buf = 0;
    return;
  }

  entity_buf = malloc(entity_len);
  if (entity_buf == 0)
    die(0, "malloc");

  nr = fread(entity_buf, 1, entity_len, stdin);
  if (nr == 0) {
    free(entity_buf);
    entity_len = 0;
    entity_buf = 0;
  }
}


static char ibuf[1024];		/* input buffer */
static jmp_buf reopen_socket;	/* bailout when server shuts down */
#define buf_size 1024		/* output buffer size */
static char buf[buf_size];	/* output buffer */
static char* bufp;		/* current position in output buffer */
static int buf_left;		/* space left in output buffer */
static int sock;		/* socket fd */

DEBUG(static FILE* debug);

/* Open the unix file socket and make a connection to the server.  If
 * the server isn't listening on the socket, retry for LINK_TIMEOUT
 * seconds.
 */
static void open_socket()
{
  struct sockaddr_un sa;
  int size;
  int s;
  int i;
  int e;
  int r;
  uid_t euid;
  gid_t egid;


  sa.sun_family = AF_UNIX;
  strcpy(sa.sun_path, LINK_FILE);
#ifdef offsetof
  size = (offsetof (struct sockaddr_un, sun_path) + strlen (sa.sun_path) + 1);
#else
  size = sizeof(sa.sun_family) + strlen(sa.sun_path) + 1;
#endif

  for (i = 0;  i < LINK_TIMEOUT;  ++i) {
    sock = socket(PF_UNIX, SOCK_STREAM, 0);
    e = errno;
    if (sock < 0)
      die(e, "Could not open socket");

    do {
      s = connect(sock, (struct sockaddr*) &sa, size);
      e = errno;
    } while (s == -1 && e == EINTR);

    if (s == 0)
      break;
    close(sock);
    sleep(1);
  }
  if (s < 0) {

	/* If NET_START not "-notify" or "-netstart", this will exit */
    server_not_running();


  /* Prevend Vend from thinking it is being called as CGI */

#ifdef USE_PUTENV
  putenv("GATEWAY_INTERFACE=");
#else
  setenv("GATEWAY_INTERFACE", "", 1);
#endif

  euid = geteuid();
  r = setreuid( euid, euid );
  if (r == -1) {
    printf("Content-type: text/plain\n\n");
    printf("Could not set uid: %s\n", ERRMSG(errno));
    exit(1);
  }

  egid = getegid();
  r = setregid( egid, egid );
  if (r == -1) {
    printf("Content-type: text/plain\n\n");
    printf("Could not set gid: %s\n", ERRMSG(errno));
    exit(1);
  }
	fclose(stdout);
	execl(PERL, PERL, VEND, NET_START, 0); 
	fprintf(stderr, "Could not exec %s: %s", PERL, ERRMSG(errno));
    exit(1);
  }
}

/* Close the socket connection.
 */
static void close_socket()
{
  if (close(sock) < 0)
    die(errno, "close");
}

/* Write out the output buffer to the socket.  If the cgi-bin server
 * has 'listen'ed on the socket but closes it before 'accept'ing our
 * connection, we'll get a EPIPE here and retry the connection over again.
 */
static void write_out()
{
  char* p = buf;
  int len = bufp - buf;
  int w;

  while (len > 0) {
    do {
      w = write(sock, p, len);
    } while (w < 0 && errno == EINTR); /* retry on interrupted system call */
    if (w < 0 && errno == EPIPE) /* server closed */
      longjmp(reopen_socket, 1); /* try to reopen the connection */
    if (w < 0)
      die(errno, "write");
    p += w;			/* write the rest out if short write */
    len -= w;
  }

  bufp = buf;			/* reset output buffer */
  buf_left = buf_size;
}

/* Write out LEN characters from STR to the cgi-bin server.
 */
static void out(len, str)
     int len;
     char* str;
{
  char* strp = str;
  int str_left = len;

  while (str_left > 0) {
    if (str_left < buf_left) {	       /* all fits in buffer */
      memcpy(bufp, strp, str_left);
      bufp += str_left;
      buf_left -= str_left;
      str_left = 0;
    } else {			       /* only part fits */
      memcpy(bufp, strp, buf_left);    /* copy in as much as fits */
      str_left -= buf_left;
      strp += buf_left;
      bufp += buf_left;
      write_out();		       /* write out buffer */
    }
  }
}

/* Writes the null-terminated STR to the cgi-bin server.
 */
static void outs(str)
     char* str;
{
  out(strlen(str), str);
}

/* Returns I as an ascii string.  Don't some systems define itoa for you?
 */
static char* itoa(i)
     int i;
{
  static char buf[32];
  sprintf(buf, "%d", i);
  return buf;
}

/* Sends the null-terminated value STR to the cgi-bin server.  First
 * writes the length, then a space, then the value, and finally an
 * aesthetic newline.
 */
static void outv(str)
     char* str;
{
  int len = strlen(str);

  outs(itoa(len));
  out(1, " ");
  out(len, str);
  out(1, "\n");
}

/* Send the program arguments (but not the program name argv[0])
 * to the server.
 */
static void send_arguments(argc, argv)
     int argc;
     char** argv;
{
  int i;

  outs("arg ");
  outs(itoa(argc - 1));		       /* number of arguments */
  outs("\n");
  for (i = 1;  i < argc;  ++i) {
    outv(argv[i]);
  }
}

/* Send the environment to the server.
 */
static void send_environment()
{
  int n;
  char** e;

  /* count number of env variables */
  for (e = environ, n = 0;  *e != 0;  ++e, ++n)
    ;

  outs("env ");
  outs(itoa(n));		       /* number of vars */
  outs("\n");
  for (e = environ;  *e != 0;  ++e) {
    outv(*e);
  }
}

/* Send entity if we have one.
 */
static void
send_entity()
{
  char* cl;
  int len;
  int left;
  int tr;

  if (entity_len > 0) {
    outs("entity\n");
    outs(itoa(entity_len));
    out(1, " ");
    out(entity_len, entity_buf);
    out(1, "\n");
  }
}

#define BUFSIZE 16384

struct buffer {
  int len;
  int written;
  struct buffer* nextbuf;
  char buf[BUFSIZE];
};

static struct buffer* new_buffer()
{
  struct buffer* buf = (struct buffer*) malloc(sizeof(struct buffer));
  if (buf == 0)
    die(0, "malloc");
  DEBUG(fprintf(debug, "new buffer %p\n", buf));
  buf->len = 0;
  buf->written = 0;
  buf->nextbuf = 0;
  return buf;
}

static int read_from_server(bp)
     struct buffer* bp;
{
  int b;
  int n;
  char* a;

  b = BUFSIZE - bp->len;
  DEBUG(fprintf(debug, "read %d bytes into buffer %p at %d", b, bp, bp->len));
  a = (bp->buf) + bp->len;
  DEBUG(fprintf(debug, " addr is %p", a));
  do {
    n = read(sock, a, b);
  } while (n < 0 && errno == EINTR);
  if (n < 0)
    die(errno, "read");
  if (n == 0) {
    DEBUG(fprintf(debug, " eof\n"));
    DEBUG(fflush(debug));
    return 0;
  }
  DEBUG(fprintf(debug, "  got %d <", n));
  DEBUG(fwrite(bp->buf + bp->len, n, 1, debug));
  DEBUG(fprintf(debug, ">\n"));
  DEBUG(fflush(debug));
  bp->len += n;
  return 1;
}

static int write_to_client(bp)
     struct buffer* bp;
{
  int b = bp->len - bp->written;
  int n;

  DEBUG(fprintf(debug, "write %d bytes from buf %p at %d", b, bp, bp->written));
  DEBUG(fflush(debug));
  do {
    n = write(CGIOUT, bp->buf + bp->written, b);
  } while (n < 0 && errno == EINTR);
  if (n < 0 && errno == EAGAIN)
    return 0;
  if (n < 0)
    die(errno, "write");
  DEBUG(fprintf(debug, "  wrote %d <", n));
  DEBUG(fwrite(bp->buf + bp->written, n, 1, debug));
  DEBUG(fprintf(debug, ">\n"));
  DEBUG(fflush(debug));
  bp->written += n;
  return (bp->written == bp->len);
}

static void return_response()
{
  int reading;
  int writing;
  fd_set readfds;
  fd_set writefds;
  int maxfd;
  int r;
  struct buffer* readbuf;
  struct buffer* writebuf;
  struct buffer* newbuf;

  int f;
  if (fcntl(CGIOUT, F_SETFL, O_NONBLOCK) < 0)
    die(errno, "fcntl");
  f = fcntl(CGIOUT, F_GETFL);
  DEBUG(fprintf(debug, "CGIOUT nonblock flag %d\n", f & O_NONBLOCK));

  reading = 1;
  readbuf = writebuf = new_buffer();

  for (;;) {
    if (writebuf->written == BUFSIZE && writebuf->nextbuf != 0) {
      newbuf = writebuf->nextbuf;
      DEBUG(fprintf(debug, "new writebuf %p, free old writebuf %p\n", newbuf, writebuf));
      free(writebuf);
      writebuf = newbuf;
    }

    writing = (writebuf->written < writebuf->len);
    DEBUG(fprintf(debug, "writebuf %p, written %d, len %d: writing %d\n", writebuf, writebuf->written, writebuf->len, writing));

    if (!reading && !writing)
      break;
      
    FD_ZERO(&readfds);
    FD_ZERO(&writefds);
    maxfd = 0;
    if (reading) {
      FD_SET(sock, &readfds);
      maxfd = sock;
    }
    if (writing) {
      FD_SET(CGIOUT, &writefds);
      if (maxfd < CGIOUT)
        maxfd = CGIOUT;
    }

    r = select(maxfd + 1, &readfds, &writefds, 0, 0);
    if (r < 0)
      die(errno, "select");

    if (reading && FD_ISSET(sock, &readfds)) {
      if (readbuf->len == BUFSIZE) {
        newbuf = new_buffer();
        readbuf->nextbuf = newbuf;
        readbuf = newbuf;
      }
      r = read_from_server(readbuf);
      if (r == 0)
        reading = 0;
    }

    if (writing && FD_ISSET(CGIOUT, &writefds)) {
      r = write_to_client(writebuf);
      DEBUG(fprintf(debug, "after write, writebuf %p, written %d, len %d\n", writebuf, writebuf->written, writebuf->len));
    }
  }
}


#if 0
/* Now read the response from the cgi-bin server and return it to our
 * caller (httpd).  We assume the server just closes the socket at the
 * end of the response.
 */
static void read_sock()
{
  int nr;
  char* p;
  int w;

  for (;;) {
    do {
      nr = read(sock, ibuf, sizeof(ibuf));
    } while (nr < 0 && errno == EINTR);	/* interrupted system call */
    if (nr < 0)
      die(errno, "read");
    if (nr == 0)		       /* that's it, all done */
      break;

    p = ibuf;			       /* write it to our stdout */
    while (nr > 0) {
      do {
	w = write(CGIOUT, p, nr);
      } while (w < 0 && errno == EINTR);
      if (w < 0)
	die(errno, "write");
      p += w;			       /* and write again if short write */
      nr -= w;
    }
  }
}
#endif

int main(argc, argv)
     int argc;
     char** argv;
{
  DEBUG(debug = fopen("/tmp/link.debug", "w"));
  DEBUG(if (debug == 0) die(errno, "open"));

  /* Give us an EPIPE error instead of a SIGPIPE signal if the server
   * closes the socket on us.
   */
  if (signal(SIGPIPE, SIG_IGN) == SIG_ERR)
    die(errno, "signal");

  get_entity();

  /* If the server does close the socket, jump back here to reopen. */
  if (setjmp(reopen_socket)) {
    close_socket();		       /* close our end of old socket */
  }

  bufp = buf;			       /* init output buf */
  buf_left = buf_size;
  open_socket();		       /* open our connection */
  send_arguments(argc, argv);
  send_environment();
  send_entity();
  outs("end\n");
  write_out();			       /* flush output buffer */

  return_response();
  close_socket();
  return 0;
}