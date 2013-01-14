/*
 * FINF - FINF Is Not Forth
 * Version 0.1.7
 * Copyright (c) 2005-2011 Leandro A. F. Pereira <leandro@tia.mat.br>
 * Licensed under GNU GPL version 2.
 */
#include <avr/pgmspace.h>
#include <EEPROM.h>
#include <AFMotor.h>

/*
 * Uncomment if building to use on a terminal program
 * (instead of Arduino's Serial Monitor) -- uses ~800bytes
 * of flash + ~40bytes of RAM
 */
#define TERMINAL 1

#define MAX_WORDS   100
#define MAX_PROGRAM 64
#define MAX_STACK   16

#define STATE_INITIAL     0
#define STATE_DEFWORD     1
#define STATE_ADDCODE     2
#define STATE_ADDNUM      3
#define STATE_DEFINE_VARIABLE 4
#define STATE_DEFINE_CONST   5

#define RELAY_BASE_PIN 4

#define PAD_SIZE 128  // size of the character pad, when allocated

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
  OP_GT,
  OP_AUTO,  // stores a value in the first (0th) position in the EEPROM. On start of FINF, 
            // if that value == 1, assumes the text in the EEPROM is a program, and then loads and executes that text.
  OP_RELAY, // add RELAY_BASE_PIN to the number on the stack in order to get the right pin number
  OP_IN,    // set pin to digital read
  OP_OUT,   // set pin to digital write
  OP_ON,    // turn digital pin on
  OP_OFF,   // turn digital pin off
  OP_LED,   // the LED pin number
  OP_PWM,   // set PWM on pin
  OP_RESET,            // reset the arduino board
  OP_SAVE_TO_EEPROM,   // reads text from Serial into the EEPROM. ^Z quits
  OP_LOAD_FROM_EEPROM, // executes the text in the EEPROM. Text starts at the 1st postition.
                       // 0th positions indicates whether to autoload on device start.
  OP_LIST_EEPROM,      // outputs the text in the EEPROM to the serial device.
  OP_ERASE_EEPROM,     // erases all text in the EEPROM. Does this by putting a 0 in position 1. All other trxt is preserved.
  OP_STORE,            // ( value address "!" -- ) Implements the FORTH "!" opcode. Stores value in SRAM.
  OP_FETCH,            // ( address "@" -- memory-location-contents-as-int ) implements the FORTH "@" opcode. Pulls SRAM address-value to the stack.
  OP_FETCH_AND_PRINT,  // ( address "?" -- ) prints the value stored in an address
  OP_VARIABLE,         // ( "var or variable" varname -- ) creates a variable of name "varname". "var" or "variable" both execute this.
  OP_EEPROM_STORE,     // ( value eeprom-address "e!" -- ) stores an integer in an EEPROM address
  OP_EEPROM_FETCH,     // ( eeprom-address "e@" -- eeprom-address-contents ) gets the value of the EEPROM location, and puts it on the stack. 
  OP_EEPROM_FETCH_AND_PRINT, // ( eeprom-address "e?" -- ) prints the value at the given EEPROM address
  OP_KEY,              // waits for a keypress and stores the value on the stack
  OP_STEPPER_MOTOR,    // ( steps direction port 'step' -- ) run a stepper motor attached to an AdaFruit MShield
  OP_DC_MOTOR,         // ( speed direction port 'motor' -- ) run a DC motor attached to an AdaFruit MShield. Directions are 1,2, motors are 1-4.
  OP_DC_MOTORS_FORWARD, // ( speed motor_bank 'forward' -- ) on an AdaFruit MShield, start both DC motors on the specified bank running so that a skid-steer two motor robot would move forward.
  OP_DC_MOTORS_BACKWARD, // ( speed motor_bank 'back' -- )  on an AdaFruit MShield, start both DC motors on the specified bank running so that a skid-steer two motor robot would move backward.
  OP_DC_MOTORS_TURN,   // ( direction speed motor_bank 'turn' -- )  on an AdaFruit MShield, start both DC motors on the specified bank running so that a skid-steer two motor robot would turn in the specified direction.
  OP_DC_MOTORS_STOP,   // ( motor_bank 'stop' -- ) stop both motors attached to the specified bank of an AdaFruit MShield.
  OP_GET_PAD_ADDRESS,  // ( "pad" -- pad-address ) if area for the PAD has not been allocated, allocate PAD_LENGTH bytes. Return the location on the stack.
  OP_DEFINE_CONST,     // ( value "const" constname ) define a constant of value "value" and name "constname"
  OP_READ_LINE,        // ( memory-address max-length "readln" -- bytes-received ) read from the serial port into the memory locaiton specified, 
                       // until max-length bytes are received, or carriage return or line feed are received.
  OP_PRINT_MEMORY_STRING, // ( mwmory-address "print" -- ) prints the contents of a memory location to the serial port
  OP_MOVE_MEMORY,         // ( source-address target-address length "move" -- ) executes memmove
  OP_GET_STRING_LENGTH,   // ( memory-address "strlen" -- ) executes strlen
};

struct Word {
  union {
    char *user;
    PGM_P internal;
  } 
  name;
  union {
    char opcode;
    unsigned char entry;
  } 
  param;
}  
__attribute__((packed));

struct Program {
  unsigned char opcode;
  int param;
} 
__attribute__((packed));

struct DefaultWord {
  PGM_P name;
  char opcode;
} 
__attribute__((packed));

const char hidden_ops_str[] PROGMEM = "num\0wrd\0ret\0prn";
const char default_words_str[] PROGMEM = "+\0"
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
          ">\0"
          "auto\0"
          "in\0"
          "out\0"
          "on\0"
          "off\0"
          "relay\0"
          "led\0"
          "pwm\0"
          "reset\0"
          "load\0"
          "save\0"
          "list\0"
          "erase\0"
          "!\0"
          "@\0"
          "?\0"
          "variable\0"
          "e!\0"
          "e@\0"
          "e?\0"  
          "key\0" 
          "step\0"  
          "motor\0"  
          "forward\0"
          "back\0"
          "turn\0" 
          "stop\0"
          "pad\0" 
          "var\0"
          "const\0"
          "readln\0"
          "print\0"
          "move\0"
          "strlen\0"
          ;

#define DW(pos) (&default_words_str[pos])
const DefaultWord default_words[] PROGMEM = {
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
  { DW(141), OP_AUTO },
  { DW(146), OP_IN }, 
  { DW(149), OP_OUT }, 
  { DW(153), OP_ON },
  { DW(156), OP_OFF },
  { DW(160), OP_RELAY },
  { DW(166), OP_LED },
  { DW(170), OP_PWM },
  { DW(174), OP_RESET },
  { DW(180), OP_LOAD_FROM_EEPROM },
  { DW(185), OP_SAVE_TO_EEPROM },
  { DW(190), OP_LIST_EEPROM },
  { DW(195), OP_ERASE_EEPROM },
  { DW(201), OP_STORE },
  { DW(203), OP_FETCH },
  { DW(205), OP_FETCH_AND_PRINT },
  { DW(207), OP_VARIABLE },
  { DW(216), OP_EEPROM_STORE },
  { DW(219), OP_EEPROM_FETCH },
  { DW(222), OP_EEPROM_FETCH_AND_PRINT },
  { DW(225), OP_KEY },
  { DW(229), OP_STEPPER_MOTOR },
  { DW(234), OP_DC_MOTOR },
  { DW(240), OP_DC_MOTORS_FORWARD },
  { DW(248), OP_DC_MOTORS_BACKWARD },
  { DW(253), OP_DC_MOTORS_TURN },
  { DW(258), OP_DC_MOTORS_STOP },
  { DW(263), OP_GET_PAD_ADDRESS },
  { DW(267), OP_VARIABLE },
  { DW(271), OP_DEFINE_CONST },
  { DW(277), OP_READ_LINE },
  { DW(284), OP_PRINT_MEMORY_STRING },
  { DW(290), OP_MOVE_MEMORY },
  { DW(295), OP_GET_STRING_LENGTH },

  { NULL, 0 },
};

#define DEFAULT_WORDS_LEN (sizeof(default_words) / sizeof(default_words[0]) - 1)
#define WORD_IS_OPCODE(wid) (((wid) < DEFAULT_WORDS_LEN))
#define WORD_IS_USER(wid) (!WORD_IS_OPCODE((wid)))
#undef DW

Program program[MAX_PROGRAM];
Word words[MAX_WORDS];
int stack[MAX_STACK];
int wc = -1, sp = 0, bufidx = 0;
char mode = 0, state = STATE_INITIAL;
unsigned int pc = 0, scratch_pc = 0;
int last_pc, last_wc;
char buffer[16];
char open_if = 0, open_begin = 0, open_scratch = 0;
char *pad = NULL;
bool is_variable_definition = true;

#ifdef TERMINAL
char term_buffer[64];
char term_bufidx = 0;
#endif /* TERMINAL */

#ifndef isdigit
char isdigit(unsigned char ch)
{
  return ch >= '0' && ch <= '9';
}
#endif

#ifndef isspace
char isspace(unsigned char ch)
{
  return !!strchr_P(PSTR(" \t\r\r\n"), ch);
}
#endif

void serial_print_P(const char *msg)
{
#ifdef TERMINAL
  char buf[32];
#else
  char buf[20];
#endif
  strncpy_P(buf, msg, sizeof(buf));
  Serial.print(buf);
}

char error(char *msg)
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
      pc = scratch_pc;
      open_scratch = 0;
    } 
    else {
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

char error(char *msg, char param)
{
  error(msg);
  Serial.println(param);
  return 0;
}

char error(char *msg, char *param)
{
  error(msg);
  Serial.println(param);
  return 0;
}

void stack_push(int value)
{
  if (sp + 1 > MAX_STACK) 
    error(PSTR("Stack overflow"));
  else 
    stack[++sp] = value;
}

int stack_pop(void)
{
  if (sp < 0) {
    error(PSTR("Stack underflow"));
    return 0;
  }
  return stack[sp--];
}

char word_new_user(char *name)
{
  if (++wc >= MAX_WORDS) return -1;
  words[wc].name.user = name;
  words[wc].param.entry = pc;
  return wc;
}

char word_new_opcode(PGM_P name, unsigned char opcode)
{
  if (++wc >= MAX_WORDS) return -1;
  words[wc].name.internal = name;
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

char word_get_id(const char *name)
{
  for (char i = wc; i >= 0; i--) {
    if (WORD_IS_OPCODE(i)) {
      if (!strcmp_P(name, words[i].name.internal))
        return i;
    } 
    else {
      if (!strcmp(name, words[i].name.user))
        return i;
    }
  }
  return -1;
}

char word_get_id_from_pc(char pc)
{
  for (char i = wc; i >= DEFAULT_WORDS_LEN; i--) {
    if (words[i].param.entry == pc)
      return i;
  }
  return -1;
}

char word_get_id_from_opcode(unsigned char opcode)
{
  for (char i = DEFAULT_WORDS_LEN - 1; i >= 0; i--) {
    if (words[i].param.opcode == opcode)
      return i;
  }
  return -1;
}

void word_print_name(char wid)
{
  if (wid < 0 || wid > wc) {
    error(PSTR("invalid word id"));
    return;
  }
  if (WORD_IS_OPCODE(wid)) {
    serial_print_P((char*)words[wid].name.internal);
  } 
  else {
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
      } 
      else if (program[i].opcode == OP_CALL) {
        Serial.print(' ');
        word_print_name(program[i].param);
      }
    } 
    else {
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

void eval_code(unsigned char opcode, int param, char mode)
{
  int pin;
  int addr; 
  int val;

  if (mode == 1 || (open_scratch && mode != 3)) {
    if (pc >= MAX_PROGRAM) {
      error(PSTR("Max program size reached"));
      return;
    }
    program[pc].opcode = opcode;
    program[pc++].param = param;
  } 
  else {
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

    case OP_PWM:
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
          if (WORD_IS_OPCODE(i)) {
            serial_print_P(PSTR("\033[40;36m"));
          } 
          else {
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
        Serial.println("Word count: ");
        Serial.println(i);
      }
      break;

    case OP_SHOWSTACK:
      {
        for (char i = sp; i > 0; i--) {
          Serial.print((int)stack[i]);
          Serial.print(' ');  
        }
        Serial.println();
      }
      break;

    case OP_CALL:
      {
        if (WORD_IS_OPCODE(param)) {
          eval_code(words[param].param.opcode, param, mode);
        } 
        else {
          open_scope(words[param].param.entry, OP_RET);
        }
      }
      break;

    case OP_AUTO:
      EEPROM.write(0, stack_pop());
      break;

    case OP_RELAY:
      stack_push(stack_pop() + RELAY_BASE_PIN);
      break; 

    case OP_IN:
      pinMode(stack_pop(), 0);
      break;

    case OP_OUT: 
      pin = stack_pop();
      pinMode(pin, 1);
      digitalWrite(pin, HIGH);
      break;

    case OP_ON:
      digitalWrite(stack_pop(), HIGH);
      break;

    case OP_OFF:
      digitalWrite(stack_pop(), LOW);
      break;

    case OP_LED:
      stack_push(13);
      break;

    case OP_RESET:
      void (*reset)();
      reset=0;
      reset();
      break;

    case OP_SAVE_TO_EEPROM:
      save_to_eeprom();
      break;

    case OP_LOAD_FROM_EEPROM:
      load_from_eeprom();
      break;

    case OP_LIST_EEPROM:
      list_eeprom();
      break;

    case OP_ERASE_EEPROM:
      erase_eeprom();
      break;

    case OP_STORE:
      addr = stack_pop();
      *((int *)addr) = stack_pop();
      break;   

    case OP_FETCH:
      addr = stack_pop();
      stack_push(*((int *)addr));
      break;

    case OP_FETCH_AND_PRINT:
      addr = stack_pop();
      Serial.print(*((int *)addr));
      break;

    case OP_EEPROM_STORE:
      EEPROM.write(stack_pop(), stack_pop());
      break;

    case OP_EEPROM_FETCH:
      stack_push(EEPROM.read(stack_pop()));
      break;

    case OP_EEPROM_FETCH_AND_PRINT:
      Serial.print(EEPROM.read(stack_pop()));
      break;

    case OP_KEY:
      while(!Serial.available());
      stack_push(Serial.read());
      break;

    case OP_STEPPER_MOTOR:
      run_steppers();
      break;

    case OP_DC_MOTOR:
      run_dcmotor();
      break;

    case OP_DC_MOTORS_FORWARD:
      run_dcmotors_forward();
      break;

    case OP_DC_MOTORS_BACKWARD:
      run_dcmotors_backward();
      break;

    case OP_DC_MOTORS_TURN:
      run_dcmotors_turn();
      break;

    case OP_DC_MOTORS_STOP:
      run_dcmotors_stop();
      break;

    case OP_GET_PAD_ADDRESS:
      if(NULL == pad) 
        pad = (char *)calloc(PAD_SIZE, sizeof(char));
      stack_push((int)pad);
      break;

    case OP_VARIABLE:
      state = STATE_DEFINE_VARIABLE;
      break;

    case OP_DEFINE_CONST:
      state = STATE_DEFINE_CONST;
      break;

    case OP_READ_LINE:
      readln();
      break;

    case OP_PRINT_MEMORY_STRING:
      Serial.print((char *)stack_pop());
      break;

    case OP_MOVE_MEMORY:
      {
        int len = stack_pop();
        int initial_pos = stack_pop();
        int target_pos = stack_pop();

        memmove((void *)initial_pos, (void *)target_pos, len);
      }
      break;

    case OP_GET_STRING_LENGTH:
      stack_push(strlen((char *)stack_pop()));
      break;

    default:
      serial_print_P(PSTR("Unimplemented opcode: "));
      Serial.println((int)opcode);
    }
  }
}

unsigned char open_scope(unsigned char entry, unsigned char end_opcode)
{
  while (program[entry].opcode != end_opcode) {
    if (program[entry].opcode == OP_IF) {
      if (stack_pop()) {
        entry = open_scope(entry + 1, program[program[entry].param].opcode);
      } 
      else {
        entry = open_scope(program[entry].param + 1, OP_THEN);
      }
    } 
    else if (program[entry].opcode == OP_ELSE) {
      entry = open_scope(program[entry].param, OP_THEN);
    } 
    else if (program[entry].opcode == OP_UNTIL) {
      if (stack_pop()) {
        entry = program[entry].param;
      } 
      else {
        entry++;
      }
    } 
    else {
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

char check_open_structures(void)
{
  if (open_if) {
    return error(PSTR("if without then"));
  }
  if (open_begin) {
    return error(PSTR("begin without until"));
  }
  return 1;
}

void open_scratch_program(void)
{
  if (!open_scratch++) {
    scratch_pc = pc;
  }
}

void close_scratch_program(void)
{
  if (open_scratch == 1) {
    eval_code(OP_RET, 0, mode);
    open_scope(scratch_pc, OP_RET);
  }
  open_scratch--;
}

int feed_char(char ch)
{
  if (bufidx >= sizeof(buffer)) {
    return error(PSTR("Buffer size overrun"));
  }
  switch (state) {
  case STATE_INITIAL:
    bufidx = 0;
    if (ch == ':') {
      if (wc >= MAX_WORDS) {
        return error(PSTR("Maximum number of words reached"));
      }
      state = STATE_DEFWORD;
      last_pc = pc;
      last_wc = wc;
      mode = 1;
    } 
    else if (isspace(ch)) {
      /* do nothing */
    } 
    else if (isdigit(ch)) {
      buffer[bufidx++] = ch;
      state = STATE_ADDNUM;
      mode = 2;
    } 
    else {
      buffer[bufidx++] = ch;
      state = STATE_ADDCODE;
      mode = 2;
    }
    return 1;

  case STATE_DEFINE_VARIABLE:
  case STATE_DEFINE_CONST:
    if (isspace(ch)) {
      if (bufidx > 0) {
        int value;

        last_pc = pc;
        last_wc = wc;
        buffer[bufidx] = 0;

        if (word_get_id(buffer) == -1) {
          char *dup = strdup(buffer);
          if (!dup) {
            return error(PSTR("Out of memory"));
          }
          word_new_user(dup);
          bufidx = 0;

          if(state == STATE_DEFINE_CONST)
            value = stack_pop(); 
          else
            value = (int)calloc(1, sizeof(int));

          program[pc].opcode = OP_NUM;
          program[pc++].param = value;

          program[pc].opcode = OP_RET;
          program[pc++].param = 0;

          state = STATE_INITIAL;

          return 1;
        }
        state = STATE_INITIAL;
        return error(PSTR("Word already defined"), buffer);
      } 
      else
      {
        return 1;
      }
    }
    buffer[bufidx++] = ch;
    return 1;

  case STATE_DEFWORD:
    if (isspace(ch) || ch == ';') {
      if (bufidx > 0) {
        buffer[bufidx] = 0;
        if (word_get_id(buffer) == -1) {
          char *dup = strdup(buffer);
          if (!dup) {
            return error(PSTR("Out of memory"));
          }
          word_new_user(dup);
          bufidx = 0;
          if (ch == ';') {
            eval_code(OP_RET, 0, mode);
            state = STATE_INITIAL;
          } 
          else {
            state = STATE_ADDCODE;
          }
          return 1;
        }
        return error(PSTR("Word already defined"), buffer);
      } 
      else {
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
    } 
    else if (isspace(ch) || ch == ';') {
      if (bufidx > 0) {
        buffer[bufidx] = 0;
        int wid = word_get_id(buffer);
        if (wid == -1) return error(PSTR("Undefined word"), buffer);
        if (WORD_IS_OPCODE(wid)) {
          if (!strcmp_P(buffer, PSTR("if"))) {
            if (mode == 2) {
              open_scratch_program();
            }
            stack_push(pc);
            eval_code(OP_IF, 0, mode);
            open_if++;
          } 
          else if (!strcmp_P(buffer, PSTR("else"))) {
            if (!open_if) {
              return error(PSTR("else without if"));
            }
            program[stack_pop()].param = pc;
            stack_push(pc);
            eval_code(OP_ELSE, 0, mode);
          } 
          else if (!strcmp_P(buffer, PSTR("then"))) {
            if (!open_if) {
              return error(PSTR("then without if"));
            }
            program[stack_pop()].param = pc;
            eval_code(OP_THEN, 0, mode);
            open_if--;
            if (open_scratch > 0) {
              close_scratch_program();
            }
          } 
          else if (!strcmp_P(buffer, PSTR("begin"))) {
            if (mode == 2) {
              open_scratch_program();
            }
            stack_push(pc);
            open_begin++;
          } 
          else if (!strcmp_P(buffer, PSTR("until"))) {
            if (!open_begin) {
              return error(PSTR("until without begin"));
            }
            eval_code(OP_UNTIL, stack_pop(), mode);
            open_begin--;
            if (open_scratch > 0) {
              close_scratch_program();
            }
          } 
          else {
            eval_code(words[wid].param.opcode, 0, mode);
          }
        } 
        else {
          eval_code(OP_CALL, wid, mode);
        }
        bufidx = 0;
        if (ch == ';') {
          if (!check_open_structures()) return 0;
          eval_code(OP_RET, 0, mode);
          state = STATE_INITIAL;
        }
      } 
      else if (ch != ';' && !isspace(ch)) {
        return error(PSTR("Expecting word name"));
      } 
      else if (ch == ';') {
        if (!check_open_structures()) return 0;
        eval_code(OP_RET, 0, mode);
        state = STATE_INITIAL;
      }
    } 
    else if (ch == ':') {
      if (mode == 1) return error(PSTR("Unexpected character: :"));
      bufidx = 0;
      state = STATE_DEFWORD;
      mode = 1;
    } 
    else {
      buffer[bufidx++] = ch;
    }
    return 1;

  case STATE_ADDNUM:
    if (isdigit(ch)) {
      buffer[bufidx++] = ch;
    } 
    else if (ch == ':') {
      return error(PSTR("Unexpected character: :"));
    } 
    else {
      if (bufidx > 0) {
        buffer[bufidx] = 0;
        eval_code(OP_NUM, atoi(buffer), mode);
        bufidx = 0;
        if (mode == 1) {
          if (ch == ';') {
            if (!check_open_structures()) return 0;
            eval_code(OP_RET, 0, mode);
            state = STATE_INITIAL;
          } 
          else {
            state = STATE_ADDCODE;
          }
        } 
        else {
          state = STATE_INITIAL;
        }
      } 
      else {
        return error(PSTR("This should not happen"));
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
  } 
  else {
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
  } 
  else {
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

void setup()
{
  delay(100);
  Serial.begin(9600);
  serial_print_P(PSTR(COLOR "FINF 0.1.7 - "));
  Serial.print(free_mem());
  serial_print_P(PSTR(" bytes free\r\n" ENDCOLOR));
  word_init();
#ifdef TERMINAL
  clear_buffer();
  prompt();
#endif /* TERMINAL */

  if(EEPROM.read(0))
  {
    load_from_eeprom();
    feed_char(' ');
    prompt();
  }
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

void loop()
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
void loop()
{
  if (Serial.available() > 0) {
    unsigned ch = Serial.read();
    Serial.print((char)ch);
    feed_char(ch);
  }
}
#endif /* TERMINAL */

void load_from_eeprom() 
{
  unsigned ch = 0;
  int i = 0;

  Serial.println("\r\nLoad from EEPROM:");

  do 
  {
    ch = EEPROM.read(++i);

    if(ch == '\r')
      Serial.println();
    else 
      Serial.print((char)ch);

    if(ch != 0 && ch != 255)
      feed_char(ch);
  } 
  while(ch != 0 && ch != 255);
}

void list_eeprom() 
{
  unsigned ch = 0;
  int i = 0;

  Serial.println("\r\nEEPROM contents:");

  do 
  {
    ch = EEPROM.read(++i);

    if(ch == '\r')
      Serial.println();
    else 
      Serial.print((char)ch);
  } 
  while(ch != 0);

  Serial.println();
  Serial.print(i);
  Serial.println(" bytes used.");
}

void erase_eeprom() 
{
  EEPROM.write(1, 0);
  Serial.println("\r\nEEPROM erased."); 
}

void save_to_eeprom()
{
  unsigned ch = 0;
  int i = 0;

  Serial.println("\r\nSave to EEPROM. Ctrl-Z to end.");

  do 
  {
    if (Serial.available() > 0) 
    {
      ch = Serial.read();
      EEPROM.write(++i, ch);

      if(ch == '\r')
        Serial.println();
      else 
        Serial.print((char)ch);
      //feed_char(ch);
    }
  } 
  while(ch != 0x1a);

  EEPROM.write(++i, 0);

  Serial.println("\r\nData is stored.");
}

void run_steppers() 
{
  int port = stack_pop();
  int motor_direction = stack_pop();
  int steps = stack_pop();

  int motor_speed = 30; //stack_pop();

  AF_Stepper motor(100, port);
  motor.setSpeed(motor_speed); 
  motor.step(steps, motor_direction, DOUBLE); 
}

void run_dcmotor()
{
  int port = stack_pop();
  int motor_direction = stack_pop();
  int motor_speed = stack_pop();

  AF_DCMotor motor(port);

  motor.setSpeed(200);
  motor.run(RELEASE);

  motor.run(motor_direction);
  motor.setSpeed(motor_speed);  
}

void run_dcmotors_forward() 
{
  int motor1_port;
  int motor2_port;

  int bank = stack_pop();
  int motor_speed = stack_pop();

  if(bank == 1)
  {
    motor1_port = 1;
    motor2_port = 2;
  }
  else
  {
    motor1_port = 3;
    motor2_port = 4;
  }

  AF_DCMotor motor1(motor1_port);
  AF_DCMotor motor2(motor2_port);

  motor1.setSpeed(200);
  motor1.run(RELEASE);
  motor2.setSpeed(200);
  motor2.run(RELEASE);

  motor1.run(FORWARD);
  motor1.setSpeed(motor_speed);
  motor2.run(BACKWARD);
  motor2.setSpeed(motor_speed);  
}

void run_dcmotors_backward()
{
  int motor1_port;
  int motor2_port;

  int bank = stack_pop();
  int motor_speed = stack_pop();

  if(bank == 1)
  {
    motor1_port = 1;
    motor2_port = 2;
  }
  else
  {
    motor1_port = 3;
    motor2_port = 4;
  }

  AF_DCMotor motor1(motor1_port);
  AF_DCMotor motor2(motor2_port);

  motor1.setSpeed(200);
  motor1.run(RELEASE);
  motor2.setSpeed(200);
  motor2.run(RELEASE);

  motor1.run(BACKWARD);
  motor1.setSpeed(motor_speed);
  motor2.run(FORWARD);
  motor2.setSpeed(motor_speed);  
}

void run_dcmotors_stop() 
{
  int motor1_port;
  int motor2_port;

  int bank = stack_pop();

  if(bank == 1)
  {
    motor1_port = 1;
    motor2_port = 2;
  }
  else
  {
    motor1_port = 3;
    motor2_port = 4;
  }

  AF_DCMotor motor1(motor1_port);
  AF_DCMotor motor2(motor2_port);

  motor1.setSpeed(0);
  motor1.run(RELEASE);
  motor2.setSpeed(0);
  motor2.run(RELEASE);

  motor1.run(BACKWARD);
  motor1.setSpeed(0);
  motor2.run(FORWARD);
  motor2.setSpeed(0);  
}

void run_dcmotors_turn() 
{
  int motor1_port;
  int motor2_port;
  int bank = stack_pop();
  int motor_speed = stack_pop();
  int turn_direction = stack_pop();

  if(bank == 1)
  {
    motor1_port = 1;
    motor2_port = 2;
  }
  else
  {
    motor1_port = 3;
    motor2_port = 4;
  }

  AF_DCMotor motor1(motor1_port);
  AF_DCMotor motor2(motor2_port);

  motor1.setSpeed(0);
  motor1.run(RELEASE);
  motor2.setSpeed(0);
  motor2.run(RELEASE);

  turn_direction = turn_direction == 1 ? BACKWARD : FORWARD;
  motor1.run(turn_direction);
  motor1.setSpeed(motor_speed);
  motor2.run(turn_direction);
  motor2.setSpeed(motor_speed);  
}

void readln() 
{
  int max_len = stack_pop() - 1;
  char* initial_pos = (char *)(stack_pop() - 1); 
  char* current_pos = initial_pos;
  char ch = 0;
  bool done = false;

  do
  {
    if(Serial.available())
    {
      ch = Serial.read();
      Serial.write(ch);

      switch(ch) 
      {
      case '\r':
      case '\n':
        done = true;
        break;

      case 8: // backspace
        --current_pos;
        if(current_pos < initial_pos) 
          current_pos = initial_pos;
        break;

      default:
        *(++current_pos) = ch;
        if(current_pos >= initial_pos + max_len)
          done = true;
        break;
      }
    }
  } 
  while(!done); 

  *(++current_pos) = 0;
  stack_push(current_pos - initial_pos);
  Serial.println();   
}


