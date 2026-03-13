
#ifndef HELPER_H
#define HELPER_H

/** flag SIGINT or SIGTERM have been received */
extern int force_stop;

/* External functions */
extern int init_system(void);
extern void cleanup_system(void);

#endif /* HELPER_H */