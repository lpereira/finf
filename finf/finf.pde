/*
 * FINF - FINF Is Not Forth
 * Version 0.1.6
 * Copyright (c) 2005-2010 Leandro A. F. Pereira <leandro@tia.mat.br>
 * Licensed under GNU GPL version 2.
 */
#define MAX_WORDS 48
#define MAX_PROGRAM 48
#define MAX_STACK 18

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
  OP_DISASM
};

struct Word {
  const char *name;
  union {
    unsigned char opcode;
    int entry;
  } p;
  unsigned char t: 1;
}  __attribute__((packed));

struct Program {
  unsigned char opcode;
  int param;
} __attribute__((packed));

Program program[MAX_PROGRAM];
Word words[MAX_WORDS];
int wc = 0;
int sp, pc;
int stack[MAX_STACK];
int state = STATE_INITIAL;
int last_word_id = -1;
int last_pc = -1;
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

void stack_push(int value)
{
  stack[++sp] = value;
  if (sp > MAX_STACK) {
    Serial.println("Stack overflow");
    for(;;);
  }
}

int stack_pop(void)
{
  if (sp < 0) {
    Serial.println("Stack underflow");
    return 0;
  }
  return stack[sp--];
}

int word_new_user(char *name)
{
  if (++wc >= MAX_WORDS) return -1;
  words[wc].name = name;
  words[wc].t = WT_USER;
  words[wc].p.entry = pc;
  return wc;
}

int word_new_opcode(const char *name, unsigned char opcode)
{
  if (++wc >= MAX_WORDS) return -1;
  words[wc].name = name;
  words[wc].t = WT_OPCODE;
  words[wc].p.opcode = opcode;
  return wc;
}

void word_init()
{
  struct {
    const char *name;
    unsigned char opcode;
  } const default_words[]  = {
    { "+", OP_SUM },
    { "-", OP_SUB },
    { "*", OP_MUL },
    { "/", OP_DIV },
    { ".", OP_PRINT },
    { "stk", OP_SHOWSTACK },
    { "swap", OP_SWAP },
    { "dup", OP_DUP },
    { "words", OP_WORDS },
    { "drop", OP_DROP },
    { "=", OP_EQUAL },
    { "negate", OP_NEGATE },
    { "delay", OP_DELAY },
    { "pinwrite", OP_PINWRITE },
    { "pinmode", OP_PINMODE },
    { "dis", OP_DISASM },
    { NULL, 0 },
  };
  int i;

  for (i = 0; i < MAX_WORDS; i++) {
    words[i].name = NULL;
    words[i].p.opcode = 0;
  }

  for (i = 0; default_words[i].name; i++) {
    word_new_opcode(default_words[i].name, default_words[i].opcode);
  }
}

const char *word_get_name(int id)
{
  return (id > wc) ? "nil" : words[id].name;
}

int word_get_id(const char *name)
{
  int i;
  for (i = wc; i >= 0; i--) {
    if (!strcmp(name, words[i].name)) return i;
  }
  return -1;
}

int word_get_id_from_pc(int pc)
{
  int i;
  for (i = wc; i >= 0; i--) {
    if (words[i].t == WT_USER && words[i].p.entry == pc) return i;
  }
  return -1;
}

int word_get_id_from_opcode(unsigned char opcode)
{
  int i;
  for (i = wc; i >= 0; i--) {
    if (words[i].t == WT_OPCODE && words[i].p.opcode == opcode)
      return i;
  }
  return -1;
}

void disasm()
{
  int i;
  
  for (i = 0; i < pc; i++) {

    int wid = word_get_id_from_opcode(program[i].opcode);
    Serial.print(i);
    Serial.print(' ');
    if (wid < 0) {
      Serial.print((char*[]){ "number", "call", "ret", "print"}[program[i].opcode]);
      if (program[i].opcode == OP_NUM) {
        Serial.print(' ');
        Serial.print(program[i].param);
      } else if (program[i].opcode == OP_CALL) {
        Serial.print(' ');
        Serial.print(words[program[i].param]);
      }
    } else {
      Serial.print(words[wid].name);
    }
    int curwordid = word_get_id_from_pc(i);
    if (curwordid > 0) {
      Serial.print(' ');
      Serial.print('#');
      Serial.print(' ');
      Serial.print(words[curwordid].name);
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
      case OP_DUP:
        stack_push(stack[sp]);
        break;
      case OP_EQUAL:
        stack_push(stack_pop() == stack_pop());
        break;
      case OP_NEGATE:
        stack_push(!stack_pop());
        break;
      case OP_DISASM:
        disasm();
        break;
      case OP_WORDS:
        {
          int i;
          for (i = 0; i <= wc; i++) {
            Serial.print(words[i].name);
            Serial.print(' ');
          }
          Serial.println();
        }
        break;
      case OP_SHOWSTACK:
        {
          int i;
          Serial.print("\nStack: ");
          for (i = sp; i > 0; i--) {
            Serial.print((int)stack[i]);
            Serial.print(' ');  
          }
          Serial.println();
        }
        break;
      case OP_CALL:
        {
          if (words[param].t == WT_OPCODE) {
            eval_code(words[param].p.opcode, param, mode);
          } else {
            call(words[param].p.entry);
          }
        }
        break;
      default:
        Serial.print("Unimplemented opcode: ");
        Serial.println((int)opcode);
    }
  }
}

void call(int entry)
{
  while (program[entry].opcode != OP_RET) {
    eval_code(program[entry].opcode, program[entry].param, 2);
    entry++;
  }
}

int error(const char *msg)
{
  bufidx = 0;
  Serial.print("Error: ");
  Serial.println(msg);
  return 0;
}

int error(const char *msg, char *param)
{
  bufidx = 0;
  Serial.print("Error: ");
  Serial.print(msg);
  Serial.print(": ");
  Serial.println(param);
  return 0;
}

int error(const char *msg, char param)
{
  bufidx = 0;
  Serial.print("Error: ");
  Serial.print(msg);
  Serial.print(": ");
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
          last_word_id = word_new_user(strdup(buffer));
          bufidx = 0;
          if (ch == ';') {
            eval_code(OP_RET, 0, mode);
            state = STATE_INITIAL;
          } else {
            state = STATE_ADDCODE;
          }
          return 1;
        }
        return error("Word already defined", buffer);
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
        if (wid == -1) return error("Undefined word", buffer);
        if (words[wid].t == WT_OPCODE) {
          eval_code(words[wid].p.opcode, 0, mode);
        } else {
          eval_code(OP_CALL, wid, mode);
        }
        bufidx = 0;
        if (ch == ';') {
          eval_code(OP_RET, 0, mode);
          state = STATE_INITIAL;
        }
      } else if (ch != ';' && !isspace(ch)) {
        return error("Expecting word name");
      } else if (ch == ';') {
        eval_code(OP_RET, 0, mode);
        state = STATE_INITIAL;
      }
    } else if (ch == ':') {
      if (mode == 1) return error("Unexpected character: :");
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
      return error("Unexpected character: :");
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
        return error("This should not happen");
      }
    }
    return 1;
  }
  return 0;
}

inline void setup()
{
  Serial.begin(9600);
  Serial.println("FINF 0.1.6");
  wc = -1;
  pc = 0;
  word_init();
}

inline void loop()
{
  if (Serial.available() > 0) {
    feed_char(Serial.read());
  }
}

