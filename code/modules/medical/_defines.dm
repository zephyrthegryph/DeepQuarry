#ifndef DQ_MEDICAL_DEFINES_DM
#define DQ_MEDICAL_DEFINES_DM

// Audiences a symptom can present to. A symptom may light up any subset
// of the three. Patient-only sensations rely on the player narrating;
// emotes are visible to anyone in view; scanner-visible vitals are read
// by instruments. (Body / injury / treatment defines: code/__defines/body.dm.)
#define SYMPTOM_AUDIENCE_PATIENT   (1 << 0)
#define SYMPTOM_AUDIENCE_PUBLIC    (1 << 1)
#define SYMPTOM_AUDIENCE_SCANNER   (1 << 2)

#endif // DQ_MEDICAL_DEFINES_DM
