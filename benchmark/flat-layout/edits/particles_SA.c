//@@ types
// SA (stage A of the flat layout design): AD (Double locals of move and
// bounce unboxed), plus the fields of MkParticle stored raw in its cell.
// The cell keeps its header; it has no pointer field (total = 0), so the
// runtime's release walk, the shared-flag walk and the leak walk touch none
// of it, and its size class covers the raw fields.  The array is unchanged:
// a slot holds a Just cell, which holds the MkParticle cell.  Reading a field
// is one load; building a particle is one allocation instead of five.
typedef struct {
  Idris2i_1_header header;
  uint16_t total; // pointer fields: none
  int16_t tag;
  double px;
  double py;
  double vx;
  double vy;
  int64_t hits;
} SA_Particle;
#define SA_P(v) ((SA_Particle *)(v))

static inline Idris2i_1_Value *SA_newParticle(double px, double py, double vx,
                                           double vy, int64_t hits) {
  SA_Particle *c = (SA_Particle *)idris2i_1_newValue(sizeof(SA_Particle));
  c->header.tag = CONSTRUCTOR_TAG;
  c->total = 0;
  c->tag = 0;
  c->px = px;
  c->py = py;
  c->vx = vx;
  c->vy = vy;
  c->hits = hits;
  return (Idris2i_1_Value *)c;
}

//@@ replace Main_move
Idris2i_1_Value *Main_move
(
    Idris2i_1_Value * var_0
,   Idris2i_1_Value * var_1
)
{
    SA_Particle *p = SA_P(var_0);
    SA_Particle *q = SA_P(var_1);
    double var_2 = (p->vx + (q->px - p->px) * 0.01) * 0.999;
    double var_26 = (p->vy + (q->py - p->py) * 0.01 - 0.05) * 0.999;
    double var_69 = p->px + var_2;
    double var_70 = p->py + var_26;
    int64_t var_71 = p->hits;
    idris2i_1_removeReference(var_1);
    idris2i_1_removeReference(var_0);
    Idris2i_1_Value * var_72 = SA_newParticle(var_69, var_70, var_2, var_26, var_71);
    #ifdef IDRIS2I_1_MUSTTAIL
    IDRIS2I_1_MUSTTAIL return Main_bounce(var_72);
    #else
    Idris2i_1_PendingTailCall *pending_21 = &idris2i_1_pendingTailCall;
    pending_21->f = (void *)Main_bounce;
    pending_21->arity = 1;
    pending_21->args[0] = var_72;
    return IDRIS2I_1_TAILCALL;
    #endif
}

//@@ replace Main_bounce
Idris2i_1_Value *Main_bounce
(
    Idris2i_1_Value * var_0
)
{
    SA_Particle *p = SA_P(var_0);
    Idris2i_1_Value * var_1;
    if (p->px < 0.0 || p->px > 1000.0) {
        double px = p->px < 0.0 ? -p->px : 2000.0 - p->px;
        Idris2i_1_Value *c = SA_newParticle(px, p->py, -p->vx, p->vy,
            ((int64_t)((uint64_t)(p->hits) + (uint64_t)(1))));
        idris2i_1_removeReference(var_0);
        var_1 = c;
    } else {
        var_1 = var_0;
    }
    p = SA_P(var_1);
    if (p->py < 0.0 || p->py > 1000.0) {
        double py = p->py < 0.0 ? -p->py : 2000.0 - p->py;
        Idris2i_1_Value *c = SA_newParticle(p->px, py, p->vx, -p->vy,
            ((int64_t)((uint64_t)(p->hits) + (uint64_t)(1))));
        idris2i_1_removeReference(var_1);
        return c;
    }
    return var_1;
}

//@@ replace idris2i_1_raw_Main_fill
Idris2i_1_Value *idris2i_1_raw_Main_fill
(
    int64_t int_0
,   int64_t int_1
,   Idris2i_1_Value * var_2
)
{
    idris2i_1_self_entry: ;
    int64_t primVar_0 = ((int_1) >= (int_0));
    int64_t int_22 = primVar_0;
    Idris2i_1_Value *tmp_1 = NULL;
    switch (int_22) {
    case INT64_C(0): {
        int64_t int_4 = INT64_C(7919);
        int64_t primVar_2 = ((int64_t)((uint64_t)(int_1) * (uint64_t)(int_4)));
        int64_t int_5 = primVar_2;
        int64_t int_6 = INT64_C(1000);
        int64_t primVar_3 = idris2i_1_euclidMod_Int64(int_5, int_6);
        int64_t int_7 = primVar_3;
        int64_t int_9 = INT64_C(104729);
        int64_t primVar_5 = ((int64_t)((uint64_t)(int_1) * (uint64_t)(int_9)));
        int64_t int_10 = primVar_5;
        int64_t int_11 = INT64_C(1000);
        int64_t primVar_6 = idris2i_1_euclidMod_Int64(int_10, int_11);
        int64_t int_12 = primVar_6;
        Idris2i_1_Value * var_16 = SA_newParticle((double)(int_7), (double)(int_12), 0.0, 0.0, 0);
        Idris2i_1_Value *boxVar_9 = idris2i_1_mkInt64(int_1);
        Idris2i_1_Value *callVar_10 = Data_Linear_Array_write_MArray_LinArray(var_2, boxVar_9, var_16);
        idris2i_1_removeReference(boxVar_9);
        Idris2i_1_Value * var_21 = callVar_10;
        Idris2i_1_Value * tmp_11 = NULL;
        if (NULL != var_21 /* _builtin.CONS [cons] */) {
            Idris2i_1_Value *var_17 = ((Idris2i_1_Constructor*)var_21)->args[0];
            Idris2i_1_Value *var_18 = ((Idris2i_1_Constructor*)var_21)->args[1];
            if (idris2i_1_isUnique(var_21)) {
                idris2i_1_removeReference(var_17);
                idris2i_1_freeValue(var_21);
            } else {
                idris2i_1_newReference(var_18);
                idris2i_1_dropSharedReference(var_21);
            }
            int64_t int_19 = INT64_C(1);
            int64_t primVar_12 = ((int64_t)((uint64_t)(int_1) + (uint64_t)(int_19)));
            int64_t int_20 = primVar_12;
            Idris2i_1_Value *tmp_13 = var_18;
            int64_t tmp_14 = int_20;
            var_2 = tmp_13;
            int_1 = tmp_14;
            IDRIS2I_1_SAFEPOINT();
            goto idris2i_1_self_entry;
        }
        tmp_1 = tmp_11;
      break;
    }
    default: {
        tmp_1 = var_2;
    }
    }
    return tmp_1;
}

//@@ replace idris2i_1_raw_Main_case___quotationcase_block_in_checksum_commago_quotation_0
Idris2i_1_Value *idris2i_1_raw_Main_case___quotationcase_block_in_checksum_commago_quotation_0
(
    Idris2i_1_Value * var_0
,   Idris2i_1_Value * var_1
,   Idris2i_1_Value * var_2
,   Idris2i_1_Value * var_3
,   int64_t int_4
,   Idris2i_1_Value * var_5
)
{
    Idris2i_1_Value * tmp_0 = NULL;
    if (NULL == var_5 /* _builtin.NOTHING [nothing] */) {
        int64_t int_6 = INT64_C(1);
        Idris2i_1_Value *primVar_1 = idris2i_1_mkInt64(((int64_t)((uint64_t)(int_4) + (uint64_t)(int_6))));
        Idris2i_1_Value * var_7 = primVar_1;
        #ifdef IDRIS2I_1_MUSTTAIL
        IDRIS2I_1_MUSTTAIL return Main_n___parenOpen0_comma_0_parenClose_go(var_0, var_1, var_7, var_3, var_2);
        #else
        Idris2i_1_PendingTailCall *pending_2 = &idris2i_1_pendingTailCall;
        pending_2->f = (void *)Main_n___parenOpen0_comma_0_parenClose_go;
        pending_2->arity = 5;
        pending_2->args[0] = var_0;
        pending_2->args[1] = var_1;
        pending_2->args[2] = var_7;
        pending_2->args[3] = var_3;
        pending_2->args[4] = var_2;
        return IDRIS2I_1_TAILCALL;
        #endif
    } else if (NULL != var_5 /* _builtin.JUST [just] */) {
        Idris2i_1_Value *var_8 = ((Idris2i_1_Constructor*)var_5)->args[0];
        if (idris2i_1_isUnique(var_5)) {
            idris2i_1_freeValue(var_5);
        } else {
            idris2i_1_newReference(var_8);
            idris2i_1_dropSharedReference(var_5);
        }
        int64_t int_9 = INT64_C(1);
        Idris2i_1_Value *primVar_3 = idris2i_1_mkInt64(((int64_t)((uint64_t)(int_4) + (uint64_t)(int_9))));
        Idris2i_1_Value * var_29 = primVar_3;
        // The fields are read raw; the Double accumulator stays boxed, as in
        // AD (go is not one of the functions whose locals AD unboxes).
        Idris2i_1_Value * var_15 = idris2i_1_mkDouble(SA_P(var_8)->px);
        Idris2i_1_Value *primVar_5 = idris2i_1_add_Double(var_3, var_15);
        idris2i_1_removeReference(var_3);
        idris2i_1_removeReference(var_15);
        Idris2i_1_Value * var_21 = primVar_5;
        Idris2i_1_Value * var_22 = idris2i_1_mkDouble(SA_P(var_8)->py);
        Idris2i_1_Value *primVar_7 = idris2i_1_add_Double(var_21, var_22);
        idris2i_1_removeReference(var_21);
        idris2i_1_removeReference(var_22);
        Idris2i_1_Value * var_30 = primVar_7;
        Idris2i_1_Value * var_28 = idris2i_1_mkInt64(SA_P(var_8)->hits);
        idris2i_1_removeReference(var_8);
        Idris2i_1_Value *primVar_9 = idris2i_1_add_Int64(var_2, var_28);
        idris2i_1_removeReference(var_2);
        idris2i_1_removeReference(var_28);
        Idris2i_1_Value * var_31 = primVar_9;
        #ifdef IDRIS2I_1_MUSTTAIL
        IDRIS2I_1_MUSTTAIL return Main_n___parenOpen0_comma_0_parenClose_go(var_0, var_1, var_29, var_30, var_31);
        #else
        Idris2i_1_PendingTailCall *pending_10 = &idris2i_1_pendingTailCall;
        pending_10->f = (void *)Main_n___parenOpen0_comma_0_parenClose_go;
        pending_10->arity = 5;
        pending_10->args[0] = var_0;
        pending_10->args[1] = var_1;
        pending_10->args[2] = var_29;
        pending_10->args[3] = var_30;
        pending_10->args[4] = var_31;
        return IDRIS2I_1_TAILCALL;
        #endif
    }
    IDRIS2I_1_PLAIN_RETURN return tmp_0;
}
