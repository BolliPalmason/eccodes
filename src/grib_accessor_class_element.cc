/*
 * (C) Copyright 2005- ECMWF.
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 *
 * In applying this licence, ECMWF does not waive the privileges and immunities granted to it by
 * virtue of its status as an intergovernmental organisation nor does it submit to any jurisdiction.
 */

/**************************************
 *  Enrico Fucile
 **************************************/


#include "grib_api_internal.h"
/*
   This is used by make_class.pl

   START_CLASS_DEF
   CLASS      = accessor
   SUPER      = grib_accessor_class_long
   IMPLEMENTS = unpack_long;pack_long;
   IMPLEMENTS = init
   MEMBERS=const char*    array
   MEMBERS=long    element
   END_CLASS_DEF

 */

/* START_CLASS_IMP */

/*

Don't edit anything between START_CLASS_IMP and END_CLASS_IMP
Instead edit values between START_CLASS_DEF and END_CLASS_DEF
or edit "accessor.class" and rerun ./make_class.pl

*/

static int pack_long(grib_accessor*, const long* val, size_t* len);
static int unpack_long(grib_accessor*, long* val, size_t* len);
static void init(grib_accessor*, const long, grib_arguments*);

typedef struct grib_accessor_element
{
    grib_accessor att;
    /* Members defined in gen */
    /* Members defined in long */
    /* Members defined in element */
    const char*    array;
    long    element;
} grib_accessor_element;

extern grib_accessor_class* grib_accessor_class_long;

static grib_accessor_class _grib_accessor_class_element = {
    &grib_accessor_class_long,                      /* super */
    "element",                      /* name */
    sizeof(grib_accessor_element),  /* size */
    0,                           /* inited */
    0,                           /* init_class */
    &init,                       /* init */
    0,                  /* post_init */
    0,                    /* destroy */
    0,                       /* dump */
    0,                /* next_offset */
    0,              /* get length of string */
    0,                /* get number of values */
    0,                 /* get number of bytes */
    0,                /* get offset to bytes */
    0,            /* get native type */
    0,                /* get sub_section */
    0,               /* pack_missing */
    0,                 /* is_missing */
    &pack_long,                  /* pack_long */
    &unpack_long,                /* unpack_long */
    0,                /* pack_double */
    0,                 /* pack_float */
    0,              /* unpack_double */
    0,               /* unpack_float */
    0,                /* pack_string */
    0,              /* unpack_string */
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


grib_accessor_class* grib_accessor_class_element = &_grib_accessor_class_element;

/* END_CLASS_IMP */

static void init(grib_accessor* a, const long l, grib_arguments* c)
{
    grib_accessor_element* self = (grib_accessor_element*)a;
    int n                       = 0;

    self->array   = grib_arguments_get_name(grib_handle_of_accessor(a), c, n++);
    self->element = grib_arguments_get_long(grib_handle_of_accessor(a), c, n++);
}

static int unpack_long(grib_accessor* a, long* val, size_t* len)
{
    grib_accessor_element* self = (grib_accessor_element*)a;
    int ret                     = 0;
    size_t size                 = 0;
    long* ar                    = NULL;
    grib_context* c             = a->context;

    if (*len < 1) {
        ret = GRIB_ARRAY_TOO_SMALL;
        return ret;
    }

    if ((ret = grib_get_size(grib_handle_of_accessor(a), self->array, &size)) != GRIB_SUCCESS)
        return ret;

    ar = (long*)grib_context_malloc_clear(c, size * sizeof(long));
    if (!ar) {
        grib_context_log(c, GRIB_LOG_ERROR, "unable to allocate %zu bytes", size * sizeof(long));
        return GRIB_OUT_OF_MEMORY;
    }

    if ((ret = grib_get_long_array_internal(grib_handle_of_accessor(a), self->array, ar, &size)) != GRIB_SUCCESS)
        return ret;

    if (self->element < 0 || self->element >= size) {
        grib_context_log(c, GRIB_LOG_ERROR, "Invalid element %ld for array '%s'. Value must be between 0 and %lu",
                self->element, self->array, size - 1);
        ret = GRIB_INVALID_ARGUMENT;
        goto the_end;
    }

    *val = ar[self->element];

the_end:
    grib_context_free(c, ar);
    return ret;
}

static int pack_long(grib_accessor* a, const long* val, size_t* len)
{
    grib_accessor_element* self = (grib_accessor_element*)a;
    int ret                     = 0;
    size_t size                 = 0;
    long* ar                    = NULL;
    grib_context* c             = a->context;

    if (*len < 1) {
        ret = GRIB_ARRAY_TOO_SMALL;
        return ret;
    }

    if ((ret = grib_get_size(grib_handle_of_accessor(a), self->array, &size)) != GRIB_SUCCESS)
        return ret;

    ar = (long*)grib_context_malloc_clear(c, size * sizeof(long));
    if (!ar) {
        grib_context_log(c, GRIB_LOG_ERROR, "unable to allocate %zu bytes", size * sizeof(long));
        return GRIB_OUT_OF_MEMORY;
    }

    if ((ret = grib_get_long_array_internal(grib_handle_of_accessor(a), self->array, ar, &size)) != GRIB_SUCCESS)
        return ret;

    ar[self->element] = *val;

    if ((ret = grib_set_long_array_internal(grib_handle_of_accessor(a), self->array, ar, size)) != GRIB_SUCCESS)
        return ret;

    grib_context_free(c, ar);
    return ret;
}
