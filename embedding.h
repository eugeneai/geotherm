#ifndef _EMBEDDING_H_
#define _EMBEDDING_H_

extern "C" {
  int start_embedding();
  int test_embedding();
  int end_embedding(int rc);
  jl_value_t * handle_eval_string(const char * str);
}


#endif // _EMBEDDING_H_
