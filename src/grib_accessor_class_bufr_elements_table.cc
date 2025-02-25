/*
 * (C) Copyright 2005- ECMWF.
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 *
 * In applying this licence, ECMWF does not waive the privileges and immunities granted to it by
 * virtue of its status as an intergovernmental organisation nor does it submit to any jurisdiction.
 */

/*****************************************
 *  Enrico Fucile
 ****************************************/

#include "grib_scaling.h"
#include "grib_api_internal.h"

#if GRIB_PTHREADS
static pthread_once_t once    = PTHREAD_ONCE_INIT;
static pthread_mutex_t mutex1 = PTHREAD_MUTEX_INITIALIZER;

static void thread_init()
{
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&mutex1, &attr);
    pthread_mutexattr_destroy(&attr);
}
#elif GRIB_OMP_THREADS
static int once = 0;
static omp_nest_lock_t mutex1;

static void thread_init()
{
    GRIB_OMP_CRITICAL(lock_grib_accessor_class_bufr_elements_table_c)
    {
        if (once == 0) {
            omp_init_nest_lock(&mutex1);
            once = 1;
        }
    }
}
#endif

/*
   This is used by make_class.pl

   START_CLASS_DEF
   CLASS      = accessor
   SUPER      = grib_accessor_class_gen
   IMPLEMENTS = init;unpack_string;unpack_long;unpack_double
   IMPLEMENTS = value_count; get_native_type;
   MEMBERS    =  const char* dictionary
   MEMBERS    =  const char* masterDir
   MEMBERS    =  const char* localDir
   END_CLASS_DEF

 */

/* START_CLASS_IMP */

/*

Don't edit anything between START_CLASS_IMP and END_CLASS_IMP
Instead edit values between START_CLASS_DEF and END_CLASS_DEF
or edit "accessor.class" and rerun ./make_class.pl

*/

static int get_native_type(grib_accessor*);
static int unpack_double(grib_accessor*, double* val, size_t* len);
static int unpack_long(grib_accessor*, long* val, size_t* len);
static int unpack_string(grib_accessor*, char*, size_t* len);
static int value_count(grib_accessor*, long*);
static void init(grib_accessor*, const long, grib_arguments*);

typedef struct grib_accessor_bufr_elements_table
{
    grib_accessor att;
    /* Members defined in gen */
    /* Members defined in bufr_elements_table */
    const char* dictionary;
    const char* masterDir;
    const char* localDir;
} grib_accessor_bufr_elements_table;

extern grib_accessor_class* grib_accessor_class_gen;

static grib_accessor_class _grib_accessor_class_bufr_elements_table = {
    &grib_accessor_class_gen,                      /* super */
    "bufr_elements_table",                      /* name */
    sizeof(grib_accessor_bufr_elements_table),  /* size */
    0,                           /* inited */
    0,                           /* init_class */
    &init,                       /* init */
    0,                  /* post_init */
    0,                    /* destroy */
    0,                       /* dump */
    0,                /* next_offset */
    0,              /* get length of string */
    &value_count,                /* get number of values */
    0,                 /* get number of bytes */
    0,                /* get offset to bytes */
    &get_native_type,            /* get native type */
    0,                /* get sub_section */
    0,               /* pack_missing */
    0,                 /* is_missing */
    0,                  /* pack_long */
    &unpack_long,                /* unpack_long */
    0,                /* pack_double */
    0,                 /* pack_float */
    &unpack_double,              /* unpack_double */
    0,               /* unpack_float */
    0,                /* pack_string */
    &unpack_string,              /* unpack_string */
    0,          /* pack_string_array */
    0,        /* unpack_string_array */
    0,                 /* pack_bytes */
    0,               /* unpack_bytes */
    0,            /* pack_expression */
    0,              /* notify_change */
    0,                /* update_size */
    0,             /* preferred_size */
    0,                     /* resize */
    0,      /* nearest_smaller_value */
    0,                       /* next accessor */
    0,                    /* compare vs. another accessor */
    0,      /* unpack only ith value (double) */
    0,       /* unpack only ith value (float) */
    0,  /* unpack a given set of elements (double) */
    0,   /* unpack a given set of elements (float) */
    0,     /* unpack a subarray */
    0,                      /* clear */
    0,                 /* clone accessor */
};


grib_accessor_class* grib_accessor_class_bufr_elements_table = &_grib_accessor_class_bufr_elements_table;

/* END_CLASS_IMP */

static void init(grib_accessor* a, const long len, grib_arguments* params)
{
    int n                                   = 0;
    grib_accessor_bufr_elements_table* self = (grib_accessor_bufr_elements_table*)a;

    self->dictionary = grib_arguments_get_string(grib_handle_of_accessor(a), params, n++);
    self->masterDir  = grib_arguments_get_name(grib_handle_of_accessor(a), params, n++);
    self->localDir   = grib_arguments_get_name(grib_handle_of_accessor(a), params, n++);

    a->length = 0;
    a->flags |= GRIB_ACCESSOR_FLAG_READ_ONLY;
}

static grib_trie* load_bufr_elements_table(grib_accessor* a, int* err)
{
    grib_accessor_bufr_elements_table* self = (grib_accessor_bufr_elements_table*)a;

    char* filename  = NULL;
    char line[1024] = {0,};
    char masterDir[1024] = {0,};
    char localDir[1024] = {0,};
    char dictName[1024] = {0,};
    char masterRecomposed[1024] = {0,}; /*e.g. bufr/tables/0/wmo/36/element.table */
    char localRecomposed[1024]  = {0,}; /*e.g. bufr/tables/0/local/0/98/0/element.table */
    char* localFilename   = 0;
    char** list           = 0;
    char** cached_list    = 0;
    size_t len            = 1024;
    grib_trie* dictionary = NULL;
    FILE* f               = NULL;
    grib_handle* h        = grib_handle_of_accessor(a);
    grib_context* c       = a->context;

    *err = GRIB_SUCCESS;

    len = 1024;
    if (self->masterDir != NULL)
        grib_get_string(h, self->masterDir, masterDir, &len);
    len = 1024;
    if (self->localDir != NULL)
        grib_get_string(h, self->localDir, localDir, &len);

    GRIB_MUTEX_INIT_ONCE(&once, &thread_init);
    GRIB_MUTEX_LOCK(&mutex1);

    if (*masterDir != 0) {
        char name[4096] = {0,};
        snprintf(name, 4096, "%s/%s", masterDir, self->dictionary);
        grib_recompose_name(h, NULL, name, masterRecomposed, 0);
        filename = grib_context_full_defs_path(c, masterRecomposed);
    }
    else {
        filename = grib_context_full_defs_path(c, self->dictionary);
    }

    if (*localDir != 0) {
        char localName[2048] = {0,};
        snprintf(localName, 2048, "%s/%s", localDir, self->dictionary);
        grib_recompose_name(h, NULL, localName, localRecomposed, 0);
        localFilename = grib_context_full_defs_path(c, localRecomposed);
        snprintf(dictName, 1024, "%s:%s", localFilename, filename);
    }
    else {
        snprintf(dictName, 1024, "%s", filename);
    }

    if (!filename) {
        grib_context_log(c, GRIB_LOG_ERROR, "unable to find definition file %s", self->dictionary);
        if (strlen(masterRecomposed) > 0) grib_context_log(c, GRIB_LOG_DEBUG,"master path=%s", masterRecomposed);
        if (strlen(localRecomposed) > 0) grib_context_log(c, GRIB_LOG_DEBUG, "local path=%s", localRecomposed);
        *err = GRIB_FILE_NOT_FOUND;
        dictionary = NULL;
        goto the_end;
    }

    dictionary = (grib_trie*)grib_trie_get(c->lists, dictName);
    if (dictionary) {
        /*grib_context_log(c,GRIB_LOG_DEBUG,"using dictionary %s from cache",self->dictionary);*/
        goto the_end;
    }
    else {
        grib_context_log(c, GRIB_LOG_DEBUG, "using dictionary %s from file %s", self->dictionary, filename);
    }

    f = codes_fopen(filename, "r");
    if (!f) {
        *err       = GRIB_IO_PROBLEM;
        dictionary = NULL;
        goto the_end;
    }

    dictionary = grib_trie_new(c);

    while (fgets(line, sizeof(line) - 1, f)) {
        DEBUG_ASSERT( strlen(line) > 0 );
        if (line[0] == '#') continue; /* Ignore first line with column titles */
        list = string_split(line, "|");
        grib_trie_insert(dictionary, list[0], list);
    }

    fclose(f);

    if (localFilename != 0) {
        f = codes_fopen(localFilename, "r");
        if (!f) {
            *err       = GRIB_IO_PROBLEM;
            dictionary = NULL;
            goto the_end;
        }

        while (fgets(line, sizeof(line) - 1, f)) {
            DEBUG_ASSERT( strlen(line) > 0 );
            if (line[0] == '#') continue;  /* Ignore first line with column titles */
            list = string_split(line, "|");
            /* Look for the descriptor code in the trie. It might be there from before */
            cached_list = (char**)grib_trie_get(dictionary, list[0]);
            if (cached_list) { /* If found, we are about to overwrite it. So free memory */
                int i;
                for (i = 0; cached_list[i] != NULL; ++i) free(cached_list[i]);
                free(cached_list);
            }
            grib_trie_insert(dictionary, list[0], list);
        }

        fclose(f);
    }
    grib_trie_insert(c->lists, dictName, dictionary);

the_end:
    GRIB_MUTEX_UNLOCK(&mutex1);
    return dictionary;
}

static int convert_type(const char* stype)
{
    int ret = BUFR_DESCRIPTOR_TYPE_UNKNOWN;
    switch (stype[0]) {
        case 's':
            if (!strcmp(stype, "string"))
                ret = BUFR_DESCRIPTOR_TYPE_STRING;
            break;
        case 'l':
            if (!strcmp(stype, "long"))
                ret = BUFR_DESCRIPTOR_TYPE_LONG;
            break;
        case 'd':
            if (!strcmp(stype, "double"))
                ret = BUFR_DESCRIPTOR_TYPE_DOUBLE;
            break;
        case 't':
            if (!strcmp(stype, "table"))
                ret = BUFR_DESCRIPTOR_TYPE_TABLE;
            break;
        case 'f':
            if (!strcmp(stype, "flag"))
                ret = BUFR_DESCRIPTOR_TYPE_FLAG;
            break;
        default:
            ret = BUFR_DESCRIPTOR_TYPE_UNKNOWN;
    }

    return ret;
}

static long atol_fast(const char* input)
{
    if (strcmp(input, "0") == 0)
        return 0;
    return atol(input);
}
static int bufr_get_from_table(grib_accessor* a, bufr_descriptor* v)
{
    int ret      = 0;
    char** list  = 0;
    char code[7] = { 0 };
    const size_t codeLen = sizeof(code);

    grib_trie* table = load_bufr_elements_table(a, &ret);
    if (ret)
        return ret;

    snprintf(code, codeLen, "%06ld", v->code);

    list = (char**)grib_trie_get(table, code);
    if (!list)
        return GRIB_NOT_FOUND;

#ifdef DEBUG
    {
        /* ECC-1137: check descriptor key name and unit lengths */
        const size_t maxlen_shortName = sizeof(v->shortName);
        const size_t maxlen_units     = sizeof(v->units);
        Assert( strlen(list[1]) < maxlen_shortName );
        Assert( strlen(list[4]) < maxlen_units );
    }
#endif

    strcpy(v->shortName, list[1]);
    v->type = convert_type(list[2]);
    /* v->name=grib_context_strdup(c,list[3]);  See ECC-489 */
    strcpy(v->units, list[4]);

    /* ECC-985: Scale and reference are often 0 so we can reduce calls to atol */
    v->scale  = atol_fast(list[5]);
    v->factor = codes_power<double>(-v->scale, 10);

    v->reference = atol_fast(list[6]);
    v->width     = atol(list[7]);

    return GRIB_SUCCESS;
}

int bufr_descriptor_is_marker(bufr_descriptor* d)
{
    int isMarker = 0;
    switch (d->code) {
        case 223255:
        case 224255:
        case 225255:
        case 232255:
            return 1;
    }
    if (d->F == 2 && d->X == 5)
        isMarker = 1;
    return isMarker;
}

bufr_descriptor* accessor_bufr_elements_table_get_descriptor(grib_accessor* a, int code, int* err)
{
    grib_context* c;
    bufr_descriptor* v = NULL;

    if (!a)
        return NULL;

    c = a->context;
    DEBUG_ASSERT(c);
    v = (bufr_descriptor*)grib_context_malloc_clear(c, sizeof(bufr_descriptor));
    if (!v) {
        grib_context_log(c, GRIB_LOG_ERROR,
                         "accessor_bufr_elements_table_get_descriptor: unable to allocate %ld bytes\n", sizeof(bufr_descriptor));
        *err = GRIB_OUT_OF_MEMORY;
        return NULL;
    }
    v->context = c;
    v->code    = code;
    v->F       = code / 100000;
    v->X       = (code - v->F * 100000) / 1000;
    v->Y       = (code - v->F * 100000) % 1000;

    switch (v->F) {
        case 0:
            *err = bufr_get_from_table(a, v);
            break;
        case 1:
            v->type = BUFR_DESCRIPTOR_TYPE_REPLICATION;
            break;
        case 2:
            v->type = BUFR_DESCRIPTOR_TYPE_OPERATOR;
            break;
        case 3:
            v->type = BUFR_DESCRIPTOR_TYPE_SEQUENCE;
            break;
    }

    return v;
}

static int unpack_string(grib_accessor* a, char* buffer, size_t* len)
{
    return GRIB_NOT_IMPLEMENTED;
}

static int value_count(grib_accessor* a, long* count)
{
    *count = 1;
    return 0;
}

static int get_native_type(grib_accessor* a)
{
    return GRIB_TYPE_STRING;
}

static int unpack_long(grib_accessor* a, long* val, size_t* len)
{
    return GRIB_NOT_IMPLEMENTED;
}

static int unpack_double(grib_accessor* a, double* val, size_t* len)
{
    return GRIB_NOT_IMPLEMENTED;
}
