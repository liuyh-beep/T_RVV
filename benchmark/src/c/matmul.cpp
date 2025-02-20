#include "kernel/matmul.h"
#include "support/support.h"

#define BLOCK_SIZE_M 8
#define BLOCK_SIZE_N 8
#define BLOCK_SIZE_K 8

void matmul(float *arg0, float *arg1, float *arg2, int M, int N, int K) {
  // Initialize output matrix to zero
  for (int i = 0; i < M; i++) {
    for (int j = 0; j < N; j++) {
      arg2[i * N + j] = 0;
    }
  }

  for (int i = 0; i < M; i += BLOCK_SIZE_M) {
    for (int j = 0; j < N; j += BLOCK_SIZE_N) {
      for(int k = 0; k < K; k += BLOCK_SIZE_K){
        // Calculate actual indices with modulo
        for(int ii = 0; ii < BLOCK_SIZE_M; ++ii){
          int actual_i = (i + ii) % M;
          if (i + ii >= M) continue;  // Skip if out of bounds

          for(int kk = 0; kk < BLOCK_SIZE_K; ++kk){
            if (k + kk >= K) continue;  // Skip if out of bounds

            for(int jj = 0; jj < BLOCK_SIZE_N; ++jj){
              int actual_j = (j + jj) % N;
              if (j + jj >= N) continue;  // Skip if out of bounds

              arg2[actual_i * N + actual_j] += 
                arg0[actual_i * K + (k + kk)] * 
                arg1[(k + kk) * N + actual_j];
            }
          }
        }
      }
    }
  }
}