#ifndef _INTER_H_
#define _INTER_H_

#if defined(__vita__) || defined(_WIN32)
 #define _(x) x
#else
 #include <libintl.h>
 #include <locale.h>
 #define _(x) gettext(x)
#endif

#endif /* _INTER_H_ */
