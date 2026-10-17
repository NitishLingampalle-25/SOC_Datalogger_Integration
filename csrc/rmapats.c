// file = 0; split type = patterns; threshold = 100000; total count = 0.
#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include "rmapats.h"

void  schedNewEvent (struct dummyq_struct * I1403, EBLK  * I1398, U  I624);
void  schedNewEvent (struct dummyq_struct * I1403, EBLK  * I1398, U  I624)
{
    U  I1667;
    U  I1668;
    U  I1669;
    struct futq * I1670;
    struct dummyq_struct * pQ = I1403;
    I1667 = ((U )vcs_clocks) + I624;
    I1669 = I1667 & ((1 << fHashTableSize) - 1);
    I1398->I666 = (EBLK  *)(-1);
    I1398->I667 = I1667;
    if (0 && rmaProfEvtProp) {
        vcs_simpSetEBlkEvtID(I1398);
    }
    if (I1667 < (U )vcs_clocks) {
        I1668 = ((U  *)&vcs_clocks)[1];
        sched_millenium(pQ, I1398, I1668 + 1, I1667);
    }
    else if ((peblkFutQ1Head != ((void *)0)) && (I624 == 1)) {
        I1398->I669 = (struct eblk *)peblkFutQ1Tail;
        peblkFutQ1Tail->I666 = I1398;
        peblkFutQ1Tail = I1398;
    }
    else if ((I1670 = pQ->I1306[I1669].I689)) {
        I1398->I669 = (struct eblk *)I1670->I687;
        I1670->I687->I666 = (RP )I1398;
        I1670->I687 = (RmaEblk  *)I1398;
    }
    else {
        sched_hsopt(pQ, I1398, I1667);
    }
}
void  rmaPropagate13_simv_fw_test_daidir (UB  * pcode, scalar  val)
{
    UB  * I1737;
    *(pcode + 0) = val;
    RmaRtlXEdgesHdr  * I1014 = (RmaRtlXEdgesHdr  *)(pcode + 8);
    RmaRtlEdgeBlock  * I725;
    U  I59 = I1014->I59;
    scalar  I757 = (((I59) >> (16)) & ((1 << (8)) - 1));
    US  I1547 = (1 << (((I757) << 2) + (X4val[val])));
    if (I1547 & 31692) {
        rmaSchedRtlXEdges(I1014, I1547, X4val[val]);
    }
    (I59) = (((I59) & ~(((U )((1 << (8)) - 1)) << (16))) | ((X4val[val]) << (16)));
    I1014->I59 = I59;
    {
        unsigned long long * I1796 = derivedClk + (4U * X4val[val]);
        memcpy(pcode + 104 + 4, I1796, 25U);
    }
    {
        {
            RP  * I657 = ((void *)0);
            I657 = (RP  *)(pcode + 136);
            if (I657) {
                RP  I1593 = *I657;
                if (I1593) {
                    hsimDispatchCbkMemOptNoDynElabS(I657, val, 0U);
                }
            }
        }
    }
    {
        scalar  I1626;
        scalar  I1141;
        U  I1581;
        U  I1633;
        U  I1634;
        EBLK  * I1398;
        struct dummyq_struct * pQ;
        U  I1401;
        I1401 = 0;
        pQ = (struct dummyq_struct *)ref_vcs_clocks;
        I1141 = X4val[val];
        I1626 = *(pcode + 144);
        *(pcode + 144) = I1141;
        I1581 = (I1626 << 2) + I1141;
        I1581 = 1 << I1581;
        if (I1581 & 2) {
            if (getCurSchedRegion()) {
                SchedSemiLerTBReactiveRegion_th((struct eblk *)(pcode + 152), I1401);
            }
            else {
                sched0_th(pQ, (EBLK  *)(pcode + 152));
            }
        }
        if (I1581 & 16) {
            if (getCurSchedRegion()) {
                SchedSemiLerTBReactiveRegion_th((struct eblk *)(pcode + 192), I1401);
            }
            else {
                sched0_th(pQ, (EBLK  *)(pcode + 192));
            }
        }
    }
    {
        pcode += 232;
        *((*(UB  **)(pcode + 8)) + 2) = X4val[val];
        {
            (*txpFnPtr)(pcode, 0);
        }
    }
    {
        pcode += 40;
        markMasterClkOvaLists(1, *(RP  *)(pcode + 8));
        *((*(UB  **)(pcode + 8)) + 2) = X4val[val];
        {
            (*txpFnPtr)(pcode, 0);
        }
    }
    {
        scalar  I1798 = X4val[val];
        scalar  I1799 = *(scalar  *)(pcode + 40 + 2U);
        *(scalar  *)(pcode + 40 + 2U) = I1798;
        UB  * I1014 = *(UB  **)(pcode + 40 + 8U);
        if (I1014) {
            U  I1800 = I1798 * 2;
            U  I1801 = 1 << ((I1799 << 2) + I1798);
            *(pcode + 40 + 0U) = 1;
            while (I1014){
                UB  * I1803 = *(UB  **)(I1014 + 16U);
                if ((*(US  *)(I1014 + 0U)) & I1801) {
                    *(*(UB  **)(I1014 + 48U)) = 1;
                    (*(FP  *)(I1014 + 32U))((void *)(*(RP  *)(I1014 + 40U)), (((*(scalar  *)(I1014 + 2U)) >> I1800) & 3));
                }
                I1014 = I1803;
            };
            *(pcode + 40 + 0U) = 0;
            rmaRemoveNonEdgeLoads(pcode + 40);
        }
    }
}
void  rmaPropagate160_simv_fw_test_daidir (UB  * pcode, scalar  val)
{
    UB  * I1737;
    *(pcode + 0) = val;
    {
        {
            RP  * I657 = ((void *)0);
            I657 = (RP  *)(pcode + 8);
            if (I657) {
                RP  I1593 = *I657;
                if (I1593) {
                    hsimDispatchCbkMemOptNoDynElabS(I657, val, 0U);
                }
            }
        }
    }
    pcode += 16;
    UB  * I742 = *(UB  **)(pcode + 0);
    if (I742 != (UB  *)(pcode + 0)) {
        RmaSwitchGate  * I1764 = (RmaSwitchGate  *)I742;
        RmaSwitchGate  * I956 = 0;
        do {
            RmaIbfPcode  * I1093 = (RmaIbfPcode  *)(((UB  *)I1764) + 24U);
            ((FP )(I1093->I1093))((void *)I1093->pcode, val);
            RmaDoublyLinkedListElem  I1765;
            I1765.I956 = 0;
            RmaSwitchGateInCbkListInfo  I1766;
            I1766.I1250 = 0;
            I956 = (RmaSwitchGate  *)I1764->I639.I1767.I956;
        } while ((UB  *)(I1764 = I956) != (UB  *)I742);
    }
}
#ifdef __cplusplus
extern "C" {
#endif
void SinitHsimPats(void);
#ifdef __cplusplus
}
#endif
