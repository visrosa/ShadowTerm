#pragma once
#include <libxml/tree.h>

/* libxml stores UTF-8 names as unsigned xmlChar bytes. The Vala binding
 * otherwise copies this pointer into a signed gchar temporary before a cast. */
static inline const char *
shadow_xml_node_name (const xmlNode *node)
{
    return (const char *) node->name;
}
