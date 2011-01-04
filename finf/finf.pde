/*
 * FINF - FINF Is Not Forth
 * Version 0.1.7
 * Copyright (c) 2005-2011 Leandro A. F. Pereira <leandro@tia.mat.br>
 * Licensed under GNU GPL version 2.
 */
#include <avr/pgmspace.h>

/*
 * Uncomment if building to use on a terminal program
 * (instead of Arduino's Serial Monitor)
 */
//#define TERMINAL 1

#define MAX_WORDS 64
#define MAX_PROGRAM 64
#define MAX_STACK 16

#define WT_OPCODE 0
#define WT_USER 1

#define STATE_INITIAL 0
#define STATE_DEFWORD 1
#define STATE_ADDCODE 2
#define STATE_ADDNUM 3

enum {
  OP_NUM, OP_CALL, OP_RET, OP_PRINT,
  OP_SUM, OP_SUB, OP_MUL, OP_DIV,
  OP_SWAP, OP_SHOWSTACK, OP_DUP,
  OP_WORDS, OP_DROP,
  OP_EQUAL, OP_NEGATE,
  OP_DELAY, OP_PINWRITE, OP_PINMODE,
  OP_DISASM, OP_IF, OP_ELSE, OP_THEN,
  OP_BEGIN, OP_UNTIL, OP_EMIT, OP_FREEMEM,
  OP_ANALOGREAD, OP_ANALOGWRITE, OP_PINREAD,
  OP_GT
};

struct Word {
  union {
    char *user;
    PGM_P internal;
  } name;
  union {
    char opcode;
    unsigned char entry;
  } param;
  unsigned char type: 1;
}  __attribute__((packed));

struct Program {
  unsigned char opcode;
  int param;
} __attribute__((packed));

struct DefaultWord {
  PGM_P name;
  char opcode;
} __attribute__((packed));

char hidden_ops_str[] PROGMEM = "num\0wrd\0ret\0prn";
char default_words_str[] PROGMEM = "+\0"
    "-\0"
    "*\0"
    "/\0"
    ".\0"
    "stk\0"
    "swap\0"
    "dup\0"
    "words\0"
    "drop\0"
    "=\0"
    "negate\0"
    "delay\0"
    "digwrite\0"
    "pinmode\0"
    "dis\0"
    "if\0"
    "else\0"
    "then\0"
    "begin\0"
    "until\0"
    "emit\0"
    "freemem\0"
    "digread\0"
    "analogread\0"
    "analogwrite\0"
    ">";

#define DW(pos) (&default_words_str[pos])
DefaultWord default_words[] PROGMEM = {
  { DW(0), OP_SUM },
  { DW(2), OP_SUB },
  { DW(4), OP_MUL },
  { DW(6), OP_DIV },
  { DW(8), OP_PRINT },
  { DW(10), OP_SHOWSTACK },
  { DW(14), OP_SWAP },
  { DW(19), OP_DUP },
  { DW(23), OP_WORDS },
  { DW(29), OP_DROP },
  { DW(34), OP_EQUAL },
  { DW(36), OP_NEGATE },
  { DW(43), OP_DELAY },
  { DW(49), OP_PINWRITE },
  { DW(58), OP_PINMODE },
  { DW(66), OP_DISASM },
  { DW(70), OP_IF },
  { DW(73), OP_ELSE },
  { DW(78), OP_THEN },
  { DW(83), OP_BEGIN },
  { DW(89), OP_UNTIL },
  { DW(95), OP_EMIT },
  { DW(100), OP_FREEMEM },
  { DW(108), OP_PINREAD },
  { DW(116), OP_ANALOGREAD },
  { DW(127), OP_ANALOGWRITE },
  { DW(139), OP_GT },
  { NULL, 0 },
};
#undef DW

Program program[MAX_PROGRAM];
Word words[MAX_WORDS];
int stack[MAX_STACK];
char wc = -1, sp = 0, pc = 0, bufidx = 0, mode = 0, state = STATE_INITIAL;
char last_pc, last_wc;
char buffer[16];
char open_if = 0, open_begin = 0, open_scratch = 0;

#ifdef TERMINAL
char term_buffer[32];
char term_bufidx = 0;
#endif /* TERMINAL */

#ifndef isdigit
int isdigit(unsigned char ch)
{
  return ch >= '0' && ch <= '9';
}
#endif

#ifndef isspace
int isspace(unsigned char ch)
{
  return !!strchr_P(PSTR(" \t\r\r\n"), ch);
}
#endif

void serial_print_P(char *msg)
{
#ifdef TERMINAL
  char buf[32];
#else
  char buf[20];
#endif
strncpy_P(buf, msg, sizeof(buf));
  Serial.print(buf);
}

int error(char *msg, char mode)
{
  bufidx = 0;
  if (mode == 1) {
    state = STATE_INITIAL;
    while (open_if > 0) {
      stack_pop();
      open_if--;
    }
    while (open_begin > 0) {
      stack_pop();
      open_begin--;
    }
    if (open_scratch > 0) {
      while (open_scratch > 0) {
        pc = stack_pop();
        open_scratch--;
      }
    } else {
      pc = last_pc;
    }
    if (wc != last_wc) {
      free(words[wc].name.user);
      last_wc = --wc;
    }
  }
#ifdef TERMINAL
  serial_print_P(PSTR("\033[40;31;1mError: "));
  serial_print_P(PSTR("\033[40;33m"));
  serial_print_P(msg);
  serial_print_P(PSTR("\033[0m"));
#else
  serial_print_P(PSTR("Error: "));
  serial_print_P(msg);
#endif /* TERMINAL */
  Serial.print(':');
  return 0;
}

int error(char *msg, char param, char mode)
{
  error(msg, mode);
  Serial.println(param);
  return 0;
}

int error(char *msg, char *param, char mode)
{
  error(msg, mode);
  Serial.println(param);
  return 0;
}

void stack_push(int value)
{
  stack[++sp] = value;
  if (sp > MAX_STACK) {
    error(PSTR("Stack overflow"), 0);
    for(;;);
  }
}

int stack_pop(void)
{
  if (sp < 0) {
    error(PSTR("Stack underflow"), 0);
    return 0;
  }
  return stack[sp--];
}

int word_new_user(char *name)
{
  if (++wc >= MAX_WORDS) return -1;
  words[wc].name.user = name;
  words[wc].type = WT_USER;
  words[wc].param.entry = pc;
  return wc;
}

int word_new_opcode(PGM_P name, char opcode)
{
  if (++wc >= MAX_WORDS) return -1;
  words[wc].name.internal = name;
  words[wc].type = WT_OPCODE;
  words[wc].param.opcode = opcode;
  return wc;
}

void word_init()
{
  char i;

  for (i = 0; ; i++) {
    char *name = (char *)pgm_read_word(&default_words[i].name);
    char  op   = pgm_read_byte(&default_words[i].opcode);
    if (!name) break;
    word_new_opcode(name, op);
  }

  for (; i < MAX_WORDS; i++) {
    words[i].name.internal = NULL;
    words[i].param.opcode = 0;
  }
}

int word_get_id(const char *name)
{
  char i;
  for (i = wc; i >= 0; i--) {
    if (words[i].type == WT_OPCODE) {
      if (!strcmp_P(name, words[i].name.internal))
        return i;
    } else {
      if (!strcmp(name, words[i].name.user))
        return i;
    }
  }
  return -1;
}

int word_get_id_from_pc(int pc)
{
  char i;
  for (i = wc; i >= 0; i--) {
    if (words[i].type == WT_USER && words[i].param.entry == pc)
      return i;
  }
  return -1;
}

int word_get_id_from_opcode(unsigned char opcode)
{
  char i;
  for (i = wc; i >= 0; i--) {
    if (words[i].type == WT_OPCODE && words[i].param.opcode == opcode)
      return i;
  }
  return -1;
}

void word_print_name(int wid)
{
  if (words[wid].type == WT_OPCODE) {
    serial_print_P((char*)words[wid].name.internal);
  } else {
    Serial.print(words[wid].name.user);
  }
}

void disasm()
{
  char i;
  
  for (i = 0; i < pc; i++) {
    int wid = word_get_id_from_opcode(program[i].opcode);
    Serial.print((int)i);
    Serial.print(' ');
    if (wid < 0) {
#ifdef TERMINAL
      serial_print_P(PSTR("\033[40;36;1m"));
#endif /* TERMINAL */
      serial_print_P(&hidden_ops_str[program[i].opcode * 4]);
      if (program[i].opcode == OP_NUM) {
        Serial.print(' ');
        Serial.print(program[i].param);
      } else if (program[i].opcode == OP_CALL) {
        Serial.print(' ');
        word_print_name(program[i].param);
      }
    } else {
#ifdef TERMINAL
      serial_print_P(PSTR("\033[40;36m"));
#endif /* TERMINAL */
      word_print_name(wid);
    }
#ifdef TERMINAL

      serial_print_P(PSTR("\033[0m"));
#endif /* TERMINAL */
    if (program[i].opcode == OP_IF
        || program[i].opcode == OP_ELSE
        || program[i].opcode == OP_UNTIL) {
#ifdef TERMINAL
      serial_print_P(PSTR("\033[40;36;1m goto "));
      Serial.print(program[i].param);
      serial_print_P(PSTR("\033[0m"));
#else
      serial_print_P(PSTR("goto "));
      Serial.print(program[i].param);
#endif /* TERMINAL */
    }
    int curwordid = word_get_id_from_pc(i);
    if (curwordid > 0) {
#ifdef TERMINAL
      serial_print_P(PSTR("\033[40;33m ("));
      word_print_name(curwordid);
      serial_print_P(PSTR(")\033[0m"));
#else
      serial_print_P(PSTR(" # "));
      word_print_name(curwordid);
#endif /* TERMINAL */
    }
    Serial.println();
  }
}

void stack_swap()
{
  char tmp, idx = sp - 1;
  tmp = stack[sp];
  stack[sp] = stack[idx];
  stack[idx] = tmp;
}

int free_mem() {
  extern unsigned int __bss_end;
  extern void *__brkval;
  int dummy;
  if((int)__brkval == 0)
     return ((int)&dummy) - ((int)&__bss_end);
  return ((int)&dummy) - ((int)__brkval);
}

unsigned char open_scope(unsigned char entry, char end_opcode);

void eval_code(unsigned char opcode, int param, char mode)
{
  if (mode == 1 || (open_scratch && mode != 3)) {
    if (pc >= MAX_PROGRAM) {
      error(PSTR("Max program size reached"), mode);
      return;
    }
    program[pc].opcode = opcode;
    program[pc++].param = param;
  } else {
    switch (opcode) {
      case OP_NUM:
        stack_push(param);
        break;
      case OP_SUM:
        stack_push(stack_pop() + stack_pop());
        break;
      case OP_MUL:
        stack_push(stack_pop() * stack_pop());
        break;
      case OP_SUB:
        {
          int val = stack_pop();
          stack_push(stack_pop() - val);
        }
        break;
      case OP_DIV:
        {
          int val = stack_pop();
          stack_push(stack_pop() / val);
        }
        break;
      case OP_DELAY:
        delay(stack_pop());
        break;
      case OP_PINWRITE:
        digitalWrite(stack_pop(), stack_pop());
        break;
      case OP_PINREAD:
        stack_push(digitalRead(stack_pop()));
        break;
      case OP_ANALOGREAD:
        stack_push(analogRead(stack_pop()));
        break;
      case OP_ANALOGWRITE:
        analogWrite(stack_pop(), stack_pop());
        break;
      case OP_PINMODE:
        pinMode(stack_pop(), stack_pop());
        break;
      case OP_PRINT:
        Serial.print((int)stack_pop());
        break;
      case OP_SWAP:
        stack_swap();
        break;
      case OP_DROP:
        stack_pop();
        break;
      case OP_FREEMEM:
        stack_push(free_mem());
        break;
      case OP_DUP:
        stack_push(stack[sp]);
        break;
      case OP_EQUAL:
        stack_push(stack_pop() == stack_pop());
        break;
      case OP_NEGATE:
        stack_push(!stack_pop());
        break;
      case OP_EMIT:
        Serial.print((char)stack_pop());
        break;
      case OP_DISASM:
        disasm();
        break;
      case OP_GT:
        stack_push(stack_pop() > stack_pop());
        break;
      case OP_IF:
      case OP_ELSE:
      case OP_THEN:
      case OP_BEGIN:
      case OP_UNTIL:
      case OP_RET:
        break;
      case OP_WORDS:
        {
          int i;
          for (i = 0; i <= wc; i++) {
#ifdef TERMINAL
            if (words[i].type == WT_OPCODE) {
              serial_print_P(PSTR("\033[40;36m"));
            } else {
              serial_print_P(PSTR("\033[40;33m"));
            }
#endif /* TERMINAL */
            word_print_name(i);
#ifdef TERMINAL
            serial_print_P(PSTR("\033[0m"));
#endif /* TERMINAL */
            Serial.print(' ');
          }
          Serial.println();
        }
        break;
      case OP_SHOWSTACK:
        {
          int i;
          for (i = sp; i > 0; i--) {
            Serial.print((int)stack[i]);
            Serial.print(' ');  
          }
          Serial.println();
        }
        break;
      case OP_CALL:
        {
          if (words[param].type == WT_OPCODE) {
            eval_code(words[param].param.opcode, param, mode);
          } else {
            open_scope(words[param].param.entry, OP_RET);
          }
        }
        break;
      default:
        serial_print_P(PSTR("Unimplemented opcode: "));
        Serial.println((int)opcode);
    }
  }
}

unsigned char open_scope(unsigned char entry, char end_opcode)
{
  while (program[entry].opcode != end_opcode) {
    if (program[entry].opcode == OP_IF) {
      if (stack_pop()) {
        entry = open_scope(entry + 1, OP_ELSE);
      } else {
        entry = open_scope(program[entry].param + 1, OP_THEN);
      }
    } else if (program[entry].opcode == OP_ELSE) {
      entry = open_scope(program[entry].param, OP_THEN);
    } else if (program[entry].opcode == OP_UNTIL) {
      if (stack_pop()) {
        entry = program[entry].param;
      } else {
        entry++;
      }
    } else {
      eval_code(program[entry].opcode, program[entry].param, 2 + !!open_scratch);
      entry++;
    }
    if (Serial.available() > 0 && Serial.read() == 3) {
      /* Ctrl+C pressed? */
      serial_print_P(PSTR("\r\nCtrl+C pressed\r\n"));
      break;
    }
  }
  return entry;
}

int check_open_structures(void)
{
  if (open_if) {
    return error(PSTR("if without then"), mode);
  }
  if (open_begin) {
    return error(PSTR("begin without until"), mode);
  }
  return 1;
}

void open_scratch_program(void)
{
  open_scratch++;
  stack_push(pc);
}

void run_scratch_program(void)
{
  char scratch_entry = stack_pop();
  eval_code(OP_RET, 0, mode);
  open_scope(scratch_entry, OP_RET);
  open_scratch--;
  pc = scratch_entry;
}

int feed_char(char ch)
{
  switch (state) {
  case STATE_INITIAL:
    bufidx = 0;
    if (ch == ':') {
      if (wc >= MAX_WORDS) {
        return error(PSTR("Maximum number of words reached"), mode);
      }
      state = STATE_DEFWORD;
      last_pc = pc;
      last_wc = wc;
      mode = 1;
    } else if (isspace(ch)) {
      /* do nothing */
    } else if (isdigit(ch)) {
      buffer[bufidx++] = ch;
      state = STATE_ADDNUM;
      mode = 2;
    } else {
      buffer[bufidx++] = ch;
      state = STATE_ADDCODE;
      mode = 2;
    }
    return 1;
  case STATE_DEFWORD:
    if (isspace(ch) || ch == ';') {
      if (bufidx > 0) {
        buffer[bufidx] = 0;
        if (word_get_id(buffer) == -1) {
          word_new_user(strdup(buffer));
          bufidx = 0;
          if (ch == ';') {
            eval_code(OP_RET, 0, mode);
            state = STATE_INITIAL;
          } else {
            state = STATE_ADDCODE;
          }
          return 1;
        }
        return error(PSTR("Word already defined"), buffer, mode);
      } else {
        return 1;
      }
    }
    buffer[bufidx++] = ch;
    return 1;
  case STATE_ADDCODE:
    if (bufidx == 0 && isdigit(ch)) {
      buffer[bufidx++] = ch;
      state = STATE_ADDNUM;
      return 1;
    } else if (isspace(ch) || ch == ';') {
      if (bufidx > 0) {
        buffer[bufidx] = 0;
        int wid = word_get_id(buffer);
        if (wid == -1) return error(PSTR("Undefined word"), buffer, mode);
        if (words[wid].type == WT_OPCODE) {
          if (!strcmp_P(buffer, PSTR("if"))) {
            if (mode == 2) {
              open_scratch_program();
            }
            stack_push(pc);
            eval_code(OP_IF, 0, mode);
            open_if++;
          } else if (!strcmp_P(buffer, PSTR("else"))) {
            if (!open_if) {
              return error(PSTR("else without if"), 0);
            }
            program[stack_pop()].param = pc;
            stack_push(pc);
            eval_code(OP_ELSE, 0, mode);
          } else if (!strcmp_P(buffer, PSTR("then"))) {
            if (!open_if) {
              return error(PSTR("then without if"), 0);
            }
            program[stack_pop()].param = pc;
            eval_code(OP_THEN, 0, mode);
            open_if--;
            if (open_scratch > 0) {
              run_scratch_program();
            }
          } else if (!strcmp_P(buffer, PSTR("begin"))) {
            if (mode == 2) {
              open_scratch_program();
            }
            stack_push(pc);
            open_begin++;
          } else if (!strcmp_P(buffer, PSTR("until"))) {
            eval_code(OP_UNTIL, stack_pop(), mode);
            open_begin--;
            if (open_scratch > 0) {
              run_scratch_program();
            }
          } else {
            eval_code(words[wid].param.opcode, 0, mode);
          }
        } else {
          eval_code(OP_CALL, wid, mode);
        }
        bufidx = 0;
        if (ch == ';') {
          if (!check_open_structures()) return 0;
          eval_code(OP_RET, 0, mode);
          state = STATE_INITIAL;
        }
      } else if (ch != ';' && !isspace(ch)) {
        return error(PSTR("Expecting word name"), mode);
      } else if (ch == ';') {
        if (!check_open_structures()) return 0;
        eval_code(OP_RET, 0, mode);
        state = STATE_INITIAL;
      }
    } else if (ch == ':') {
      if (mode == 1) return error(PSTR("Unexpected character: :"), mode);
      bufidx = 0;
      state = STATE_DEFWORD;
      mode = 1;
    } else {
      buffer[bufidx++] = ch;
    }
    return 1;
  case STATE_ADDNUM:
    if (isdigit(ch)) {
      buffer[bufidx++] = ch;
    } else if (ch == ':') {
      return error(PSTR("Unexpected character: :"), mode);
    } else {
      if (bufidx > 0) {
        buffer[bufidx] = 0;
        eval_code(OP_NUM, atoi(buffer), mode);
        bufidx = 0;
        if (mode == 1) {
          if (ch == ';') {
            if (!check_open_structures()) return 0;
            eval_code(OP_RET, 0, mode);
            state = STATE_INITIAL;
          } else {
            state = STATE_ADDCODE;
          }
        } else {
          state = STATE_INITIAL;
        }
      } else {
        return error(PSTR("This should not happen"), mode);
      }
    }
    return 1;
  }
  return 0;
}

#ifdef TERMINAL
void prompt()
{
  if ((state == STATE_ADDCODE && mode == 1) || open_scratch) {
    serial_print_P(PSTR("\033[40;32m...\033[0m "));
  } else {
    serial_print_P(PSTR("\033[40;32;1m>>>\033[0m "));
  }
}

void clear_buffer()
{
  term_bufidx = 0;
  memset(term_buffer, 0, sizeof(term_buffer));
}

void process_buffer()
{
  if (term_bufidx) {
    Serial.println();
    for (char i = 0; i < term_bufidx; i++) {
      feed_char(term_buffer[i]);
    }
    feed_char(' ');
    clear_buffer();
  } else {
    serial_print_P(PSTR("\r\n"));
  }
  prompt();
}
#define COLOR "\033[40;32m"
#define ENDCOLOR "\033[0m"
#else
#define COLOR
#define ENDCOLOR
#endif /* TERMINAL */

inline void setup()
{
  Serial.begin(9600);
  serial_print_P(PSTR(COLOR "FINF 0.1.7 - "));
  Serial.print(free_mem());
  serial_print_P(PSTR(" bytes free\r\n" ENDCOLOR));
  word_init();
#ifdef TERMINAL
  clear_buffer();
  prompt();
#endif /* TERMINAL */
}

#ifdef TERMINAL
void beep()
{
  Serial.print('\a');
}

void backspace()
{
  serial_print_P(PSTR("\b \b"));
}

inline void loop()
{
  if (Serial.available() > 0) {
    unsigned ch = Serial.read();
    switch (ch) {
      case '\r':  /* Carriage return */
      case '\n':  /* Linefeed */
        process_buffer();
        break;
      case 3:     /* Ctrl+C */
        serial_print_P(PSTR("^C\r\n"));
        clear_buffer();
        prompt();
        break;
      case 23:      /* Ctrl+W */
        if (term_bufidx == 0) {
          beep();
          return;
        }
        for (char i = term_bufidx; i >= 0; i--) {
          if (term_buffer[i] == ' ' || i == 0) {
            term_buffer[i] = '\0';
            for (char j = 0; j < (term_bufidx - i); j++) {
              backspace();
            }
            term_bufidx = i;
            return;
          }
        }
        break;
      case 27: /* Esc */
      case '\t':   /* Tab */
        beep();
        break;
      case '\b':  /* Ctrl+H */
      case 127:   /* Backspace */
        if (term_bufidx == 0) {
          beep();
          return;
        }
        term_buffer[term_bufidx--] = '\0';
        backspace();
        break;
      case 12:   /* Ctrl+L */
        serial_print_P(PSTR("\033[H\033[2J"));
        prompt();
        for (char c = 0; c < term_bufidx; c++) {
          Serial.print(term_buffer[c]);
        }
        break;
      default:
        if (term_bufidx >= (sizeof(term_buffer) - 2)) {
          beep();
          return;
        }
        term_buffer[term_bufidx++] = ch;
        term_buffer[term_bufidx] = '\0';
        Serial.print((char)ch);
    }
  }
}
#else
inline void loop()
{
  if (Serial.available() > 0) {
    unsigned ch = Serial.read();
    Serial.print((char)ch);
    feed_char(ch);
  }
}
#endif /* TERMINAL */

