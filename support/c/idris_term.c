#ifdef _WIN32

#include <windows.h>

#ifndef ENABLE_VIRTUAL_TERMINAL_PROCESSING
#define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x0004
#endif

void idris2i_1_setupTerm() {
  HANDLE stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);
  DWORD outmode = 0;
  GetConsoleMode(stdout_handle, &outmode);
  outmode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
  SetConsoleMode(stdout_handle, outmode);
}

int idris2i_1_getTermCols() {
  CONSOLE_SCREEN_BUFFER_INFO csbi;
  if (GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi)) {
    return (int)csbi.srWindow.Right - csbi.srWindow.Left + 1;
  }
  return 0;
}

int idris2i_1_getTermLines() {
  CONSOLE_SCREEN_BUFFER_INFO csbi;
  if (GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi)) {
    return (int)csbi.srWindow.Bottom - csbi.srWindow.Top + 1;
  }
  return 0;
}

// Interactive line editing is not available on Windows: the REPL falls back to
// plain line input.
int idris2i_1_termRawOn() { return 0; }
void idris2i_1_termRawOff() {}
int idris2i_1_readKey() { return -1; }
int idris2i_1_keyPending() { return 0; }

#else

#include <errno.h>
#include <poll.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <termios.h>
#include <unistd.h>

void idris2i_1_setupTerm() {
  // NOTE: Currently not needed for non windows systems
}


static struct termios saved_termios;
static int raw_active = 0;

void idris2i_1_termRawOff() {
  if (raw_active) {
    tcsetattr(STDIN_FILENO, TCSADRAIN, &saved_termios);
    raw_active = 0;
  }
}

// Put the terminal on stdin in raw mode (no echo, no line buffering, no signal
// characters) so that a line editor can read single keys. Returns 1 on
// success and 0 if stdin is not a terminal or can't be configured.
// Output processing stays on, so "\n" still ends a line.
int idris2i_1_termRawOn() {
  static int registered = 0;
  struct termios t;
  if (raw_active)
    return 1;
  if (!isatty(STDIN_FILENO) || tcgetattr(STDIN_FILENO, &saved_termios) != 0)
    return 0;
  t = saved_termios;
  t.c_iflag &= ~(ICRNL | IXON);
  t.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
  t.c_cc[VMIN] = 1;
  t.c_cc[VTIME] = 0;
  if (tcsetattr(STDIN_FILENO, TCSADRAIN, &t) != 0)
    return 0;
  raw_active = 1;
  if (!registered) {
    // don't leave the terminal raw if the program exits in the middle of a read
    atexit(idris2i_1_termRawOff);
    registered = 1;
  }
  return 1;
}

// Is there input that can be read without blocking (waiting up to ms)?
static int input_ready(int ms) {
  struct pollfd p = {STDIN_FILENO, POLLIN, 0};
  return poll(&p, 1, ms) > 0;
}

// Returns the next byte of input, or -1 at the end of the input.
static int next_byte() {
  unsigned char c;
  for (;;) {
    ssize_t n = read(STDIN_FILENO, &c, 1);
    if (n == 1)
      return c;
    if (n == 0 || errno != EINTR)
      return -1;
  }
}

// The next byte, if it arrives soon enough (the rest of an escape sequence is
// sent together with its start), otherwise -1.
static int next_byte_soon() { return input_ready(50) ? next_byte() : -1; }

int idris2i_1_keyPending() { return input_ready(0); }

// Key codes returned by idris2i_1_readKey. They are mirrored in
// Idris.REPL.LineEditor.
//   -1                end of input
//   0 .. 0x10FFFF     a character (control characters included)
//   KEY_ALT + c       Alt-c (or Escape followed by c)
//   KEY_SPECIAL + n   a cursor or editing key, see below
#define KEY_SPECIAL 0x200000
#define KEY_ALT 0x300000
enum {
  KEY_UP = KEY_SPECIAL + 1,
  KEY_DOWN,
  KEY_RIGHT,
  KEY_LEFT,
  KEY_HOME,
  KEY_END,
  KEY_DELETE,
  KEY_CTRL_RIGHT,
  KEY_CTRL_LEFT,
  KEY_UNKNOWN
};

// Read the rest of a CSI sequence ("ESC [" has been consumed).
static int read_csi() {
  char buf[16];
  int len = 0, c;
  for (;;) {
    c = next_byte_soon();
    if (c < 0)
      return KEY_UNKNOWN;
    if (c >= 0x40 && c <= 0x7e)
      break;
    if (len < (int)sizeof(buf) - 1)
      buf[len++] = c;
  }
  buf[len] = 0;
  // modifier 2 (shift) to 8 as in "1;5C": treat everything with a modifier
  // as the word-wise movement
  int modified = len >= 3 && buf[0] == '1' && buf[1] == ';';
  switch (c) {
  case 'A': return KEY_UP;
  case 'B': return KEY_DOWN;
  case 'C': return modified ? KEY_CTRL_RIGHT : KEY_RIGHT;
  case 'D': return modified ? KEY_CTRL_LEFT : KEY_LEFT;
  case 'H': return KEY_HOME;
  case 'F': return KEY_END;
  case '~':
    switch (atoi(buf)) {
    case 1: case 7: return KEY_HOME;
    case 3: return KEY_DELETE;
    case 4: case 8: return KEY_END;
    }
  }
  return KEY_UNKNOWN;
}

int idris2i_1_readKey() {
  int c = next_byte();
  if (c == 27) {
    int d = next_byte_soon();
    if (d < 0)
      return 27;
    if (d == '[')
      return read_csi();
    if (d == 'O') {
      int e = next_byte_soon();
      switch (e) {
      case 'A': return KEY_UP;
      case 'B': return KEY_DOWN;
      case 'C': return KEY_RIGHT;
      case 'D': return KEY_LEFT;
      case 'H': return KEY_HOME;
      case 'F': return KEY_END;
      }
      return KEY_UNKNOWN;
    }
    return KEY_ALT + d;
  }
  if (c >= 0xc0) { // UTF-8 lead byte
    int more = c >= 0xf0 ? 3 : c >= 0xe0 ? 2 : 1;
    int cp = c & (0x3f >> more);
    for (int i = 0; i < more; i++) {
      int d = next_byte_soon();
      if (d < 0 || (d & 0xc0) != 0x80)
        return 0xfffd;
      cp = (cp << 6) | (d & 0x3f);
    }
    return cp;
  }
  if (c >= 0x80) // stray continuation byte
    return 0xfffd;
  return c;
}
int idris2i_1_getTermCols() {
  struct winsize ts;
  int err = ioctl(0, TIOCGWINSZ, &ts);
  if (err) {
    err = ioctl(1, TIOCGWINSZ, &ts);
  }
  if (err)
    return 0;
  return (int)ts.ws_col;
}

int idris2i_1_getTermLines() {
  struct winsize ts;
  int err = ioctl(0, TIOCGWINSZ, &ts);
  if (err) {
    err = ioctl(1, TIOCGWINSZ, &ts);
  }
  if (err)
    return 0;
  return (int)ts.ws_row;
}

#endif
