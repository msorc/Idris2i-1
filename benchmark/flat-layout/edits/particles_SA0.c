//@@ types
// SA0: the array operations and sweep of phase 0's F0 edit (below), with the
// particles of SA (the second types block, move, bounce and checksum), and a
// fill that makes SA particles and takes F0's results.
// ownc F0: the linear array is owned (no count operations on it, nor on the
// IOArray record that it is, nor on that record's content while it is
// borrowed in an array operation), and the linear pairs (`Res`, `#`) are
// returned unboxed.  The elements (Just cells, Particle cells, Double
// boxes) are as in the as-is code: they are shared between the array and
// the reader of an element, so they stay counted.
typedef struct {
  Idris2i_1_Value *fst;
  Idris2i_1_Value *snd;
} ownc_Res;

//@@ replace Data_Linear_Array_mread_MArray_LinArray
ownc_Res Data_Linear_Array_mread_MArray_LinArray
(
    Idris2i_1_Value * var_0
,   Idris2i_1_Value * var_1
)
{
    int64_t i = idris2i_1_vp_to_Int64(var_1);
    Idris2i_1_Value *tmp_5 = NULL;
    if (i >= 0 && i < idris2i_1_vp_to_Int64(((Idris2i_1_Constructor*)var_0)->args[0])) {
        Idris2i_1_Value * var_10 = ((Idris2i_1_Constructor*)var_0)->args[1];
        Idris2i_1_Value * var_11 = (NULL /* World */);
        // call to external primitive Data_IOArray_Prims_prim__arrayGet
        Idris2i_1_Value *primVar_7 = idris2i_1_Data_IOArray_Prims_prim__arrayGet(NULL, var_10, var_1, var_11);
        tmp_5 = primVar_7;
    } else {
        tmp_5 = (NULL /* _builtin.NOTHING */);
    }
    return (ownc_Res){tmp_5, var_0};
}

//@@ replace Data_Linear_Array_write_MArray_LinArray
ownc_Res Data_Linear_Array_write_MArray_LinArray
(
    Idris2i_1_Value * var_0
,   Idris2i_1_Value * var_1
,   Idris2i_1_Value * var_2
)
{
    int64_t i = idris2i_1_vp_to_Int64(var_1);
    Idris2i_1_Value *tmp_5 = NULL;
    if (i >= 0 && i < idris2i_1_vp_to_Int64(((Idris2i_1_Constructor*)var_0)->args[0])) {
        Idris2i_1_Value * var_13 = ((Idris2i_1_Constructor*)var_0)->args[1];
         // constructor _builtin.JUST                        // Data.IOArray:47:62--47:66
        Idris2i_1_Constructor* constructor_7 = idris2i_1_newConstructor(1, 1);
                                                             // Data.IOArray:47:62--47:66
        constructor_7->args[0] = var_2;
        Idris2i_1_Value * var_14 = (Idris2i_1_Value*)constructor_7;
        Idris2i_1_Value * var_15 = (NULL /* World */);
        // call to external primitive Data_IOArray_Prims_prim__arraySet
        Idris2i_1_Value *primVar_8 = idris2i_1_Data_IOArray_Prims_prim__arraySet(NULL, var_13, var_1, var_14, var_15);
        idris2i_1_removeReference(var_14);
        Idris2i_1_Value * var_10 = primVar_8;                   // Prelude.IO:32:13--32:20
        idris2i_1_removeReference(var_10);                      // Prelude.IO:32:13--32:20
        tmp_5 = idris2i_1_mkBits8(UINT8_C(1));
    } else {
        idris2i_1_removeReference(var_2);
        tmp_5 = idris2i_1_mkBits8(UINT8_C(0));
    }
    return (ownc_Res){tmp_5, var_0};
}

//@@ replace idris2i_1_raw_Main_sweep
Idris2i_1_Value *idris2i_1_raw_Main_sweep
(
    int64_t int_0
,   int64_t int_1
,   Idris2i_1_Value * var_2
)
{
    idris2i_1_self_entry: ;
    int64_t primVar_0 = ((int_1) >= (int_0));
    if (primVar_0)
        return var_2;
    Idris2i_1_Value *boxVar_2 = idris2i_1_mkInt64(int_1);
    ownc_Res callVar_3 = Data_Linear_Array_mread_MArray_LinArray(var_2, boxVar_2);
    idris2i_1_removeReference(boxVar_2);
    Idris2i_1_Value *var_3 = callVar_3.fst;
    Idris2i_1_Value *var_4 = callVar_3.snd;
    Idris2i_1_Value * var_5 = idris2i_1_mkInt64(idris2i_1_raw_Main_next(int_0, int_1));
    ownc_Res callVar_5 = Data_Linear_Array_mread_MArray_LinArray(var_4, var_5);
    idris2i_1_removeReference(var_5);
    Idris2i_1_Value *var_6 = callVar_5.fst;
    Idris2i_1_Value *var_7 = callVar_5.snd;
    if (NULL == var_3 /* _builtin.NOTHING [nothing] */) {
        idris2i_1_removeReference(var_6);
        var_2 = var_7;
        int_1 = int_1 + 1;
        IDRIS2I_1_SAFEPOINT();
        goto idris2i_1_self_entry;
    }
    Idris2i_1_Value *var_10 = ((Idris2i_1_Constructor*)var_3)->args[0];
    if (idris2i_1_isUnique(var_3)) {
        idris2i_1_freeValue(var_3);
    } else {
        idris2i_1_newReference(var_10);
        idris2i_1_dropSharedReference(var_3);
    }
    if (NULL == var_6 /* _builtin.NOTHING [nothing] */) {
        idris2i_1_removeReference(var_10);
        var_2 = var_7;
        int_1 = int_1 + 1;
        IDRIS2I_1_SAFEPOINT();
        goto idris2i_1_self_entry;
    }
    Idris2i_1_Value *var_13 = ((Idris2i_1_Constructor*)var_6)->args[0];
    if (idris2i_1_isUnique(var_6)) {
        idris2i_1_freeValue(var_6);
    } else {
        idris2i_1_newReference(var_13);
        idris2i_1_dropSharedReference(var_6);
    }
    Idris2i_1_Value * var_14 = idris2i_1_trampoline(Main_move(var_10, var_13));
    Idris2i_1_Value *boxVar_15 = idris2i_1_mkInt64(int_1);
    ownc_Res callVar_16 = Data_Linear_Array_write_MArray_LinArray(var_7, boxVar_15, var_14);
    idris2i_1_removeReference(boxVar_15);
    idris2i_1_removeReference(callVar_16.fst);
    var_2 = callVar_16.snd;
    int_1 = int_1 + 1;
    IDRIS2I_1_SAFEPOINT();
    goto idris2i_1_self_entry;
}

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
    if (primVar_0)
        return var_2;
    int64_t primVar_2 = ((int64_t)((uint64_t)(int_1) * (uint64_t)(INT64_C(7919))));
    int64_t primVar_3 = idris2i_1_euclidMod_Int64(primVar_2, INT64_C(1000));
    int64_t primVar_5 = ((int64_t)((uint64_t)(int_1) * (uint64_t)(INT64_C(104729))));
    int64_t primVar_6 = idris2i_1_euclidMod_Int64(primVar_5, INT64_C(1000));
    Idris2i_1_Value * var_16 = SA_newParticle((double)(primVar_3), (double)(primVar_6), 0.0, 0.0, 0);
    Idris2i_1_Value *boxVar_9 = idris2i_1_mkInt64(int_1);
    ownc_Res callVar_10 = Data_Linear_Array_write_MArray_LinArray(var_2, boxVar_9, var_16);
    idris2i_1_removeReference(boxVar_9);
    idris2i_1_removeReference(callVar_10.fst);
    var_2 = callVar_10.snd;
    int_1 = int_1 + 1;
    IDRIS2I_1_SAFEPOINT();
    goto idris2i_1_self_entry;
}
