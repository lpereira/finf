/*
 * FINF - FINF Is Not Forth
 * Version 0.1.6
 * Copyright (c) 2005-2010 Leandro A. F. Pereira <leandro@tia.mat.br>
 * Licensed under GNU GPL version 2.
 */
#include <avr/pgmspace.h>

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
  OP_BEGIN, OP_UNTIL, OP_EMIT, OP_FREEMEM
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
    "pinwrite\0"
    "pinmode\0"
    "dis\0"
    "if\0"
    "else\0"
    "then\0"
    "begin\0"
    "until\0"
    "emit\0"
    "freemem";

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
  { NULL, 0 },
};
#undef DW

Program program[MAX_PROGRAM];
Word words[MAX_WORDS];
int wc = 0;
int sp, pc;
int stack[MAX_STACK];
int state = STATE_INITIAL;
char bufidx = 0, mode = 0;
char buffer[16];

#ifndef isdigit
int isdigit(unsigned char ch)
{
  return ch >= '0' && ch <= '9';
}
#endif

#ifndef isspace
int isspace(unsigned char ch)
{
  return !!strchr(" \t\r\n", ch);
}
#endif

void serial_print_P(char *msg)
{
  char buf[20];
  strncpy_P(buf, msg, sizeof(buf));
  Serial.print(buf);
}

void stack_push(int value)
{
  stack[++sp] = value;
  if (sp > MAX_STACK) {
    serial_print_P(PSTR("Stack overflow"));
    for(;;);
  }
}

int stack_pop(void)
{
  if (sp < 0) {
    serial_print_P(PSTR("Stack underflow\n"));
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
  int i;

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
  int i;
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
  int i;
  for (i = wc; i >= 0; i--) {
    if (words[i].type == WT_USER && words[i].param.entry == pc)
      return i;
  }
  return -1;
}

int word_get_id_from_opcode(unsigned char opcode)
{
  int i;
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
  int i;
  
  for (i = 0; i < pc; i++) {
    int wid = word_get_id_from_opcode(program[i].opcode);
    Serial.print(i);
    Serial.print(' ');
    if (wid < 0) {
      serial_print_P(&hidden_ops_str[program[i].opcode * 4]);
      if (program[i].opcode == OP_NUM) {
        Serial.print(' ');
        Serial.print(program[i].param);
      } else if (program[i].opcode == OP_CALL) {
        Serial.print(' ');
        word_print_name(program[i].param);
      }
    } else {
      word_print_name(wid);
    }
    if (program[i].opcode == OP_IF
        || program[i].opcode == OP_ELSE
        || program[i].opcode == OP_UNTIL) {
      Serial.print(' ');
      Serial.print(program[i].param);
      Serial.print(' ');
    }
    int curwordid = word_get_id_from_pc(i);
    if (curwordid > 0) {
      Serial.print(' ');
      Serial.print('#');
      Serial.print(' ');
      word_print_name(curwordid);
    }
    Serial.println();
  }
}

void stack_swap()
{
  int tmp, idx = sp - 1;
  tmp = stack[sp];
  stack[sp] = stack[idx];
  stack[idx] = tmp;
}

int free_mem() {
  extern unsigned int __bss_end;
  extern unsigned int __heap_start;
  extern void *__brkval;
  int dummy;
  if((int)__brkval == 0)
     return ((int)&dummy) - ((int)&__bss_end);
  return ((int)&dummy) - ((int)__brkval);
}

void call(int entry);

void eval_code(unsigned char opcode, int param, char mode)
{
  if (mode == 1) {
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
      case OP_IF:
      case OP_ELSE:
      case OP_THEN:
      case OP_BEGIN:
      case OP_UNTIL:
        break;
      case OP_WORDS:
        {
          int i;
          for (i = 0; i <= wc; i++) {
            word_print_name(i);
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
            call(words[param].param.entry);
          }
        }
        break;
      default:
        serial_print_P(PSTR("Unimplemented opcode: "));
        Serial.println((int)opcode);
    }
  }
}

void call(int entry)
{
  while (program[entry].opcode != OP_RET) {
    if (program[entry].opcode == OP_IF) {
      if (stack_pop()) {
        entry++;
      } else {
        entry = program[entry].param + 1;
      }
    } else if (program[entry].opcode == OP_ELSE) {
      entry = program[entry].param;
    } else if (program[entry].opcode == OP_UNTIL) {
      if (stack_pop()) {
        entry = program[entry].param;
      } else {
        entry++;
      }
    } else {
      eval_code(program[entry].opcode, program[entry].param, 2);
      entry++;
    }
  }
}

int error(char *msg)
{
  bufidx = 0;
  serial_print_P(PSTR("Error: "));
  serial_print_P(msg);
  Serial.print(':');
  return 0;
}

int error(char *msg, char param)
{
  error(msg);
  Serial.println(param);
  return 0;
}

int error(char *msg, char *param)
{
  error(msg);
  Serial.println(param);
  return 0;
}

int feed_char(char ch)
{
  switch (state) {
  case STATE_INITIAL:
    bufidx = 0;
    if (ch == ':') {
      state = STATE_DEFWORD;
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
        return error(PSTR("Word already defined"), buffer);
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
        if (wid == -1) return error(PSTR("Undefined word"), buffer);
        if (words[wid].type == WT_OPCODE) {
          if (mode == 1 && !strcmp_P(buffer, PSTR("if"))) {
            stack_push(pc);
            eval_code(OP_IF, 0, mode);
          } else if (mode == 1 && !strcmp_P(buffer, PSTR("else"))) {
            program[stack_pop()].param = pc;
            stack_push(pc);
            eval_code(OP_ELSE, 0, mode);
          } else if (mode == 1 && !strcmp_P(buffer, PSTR("then"))) {
            program[stack_pop()].param = pc;
            eval_code(OP_THEN, 0, mode);
          } else if (mode == 1 && !strcmp_P(buffer, PSTR("begin"))) {
            stack_push(pc);
          } else if (mode == 1 && !strcmp_P(buffer, PSTR("until"))) {
            eval_code(OP_UNTIL, stack_pop(), mode);
          } else {
            eval_code(words[wid].param.opcode, 0, mode);
          }
        } else {
          eval_code(OP_CALL, wid, mode);
        }
        bufidx = 0;
        if (ch == ';') {
          /* FIXME check if there is an open if/else/then block */
          eval_code(OP_RET, 0, mode);
          state = STATE_INITIAL;
        }
      } else if (ch != ';' && !isspace(ch)) {
        return error(PSTR("Expecting word name"));
      } else if (ch == ';') {
        eval_code(OP_RET, 0, mode);
        state = STATE_INITIAL;
      }
    } else if (ch == ':') {
      if (mode == 1) return error(PSTR("Unexpected character: :"));
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
      return error(PSTR("Unexpected character: :"));
    } else {
      if (bufidx > 0) {
        buffer[bufidx] = 0;
        eval_code(OP_NUM, atoi(buffer), mode);
        bufidx = 0;
        if (mode == 1) {
          if (ch == ';') {
            eval_code(OP_RET, 0, mode);
            state = STATE_INITIAL;
          } else {
            state = STATE_ADDCODE;
          }
        } else {
          state = STATE_INITIAL;
        }
      } else {
        return error(PSTR("This should not happen"));
      }
    }
    return 1;
  }
  return 0;
}

inline void setup()
{
  Serial.begin(9600);
  serial_print_P(PSTR("FINF 0.1.6 - "));
  Serial.print(free_mem());
  serial_print_P(PSTR(" bytes free\n"));
  wc = -1;
  pc = 0;
  word_init();
}

inline void loop()
{
  if (Serial.available() > 0) {
    unsigned ch = Serial.read();
    Serial.print((char)ch);
    feed_char(ch);
  }
}

