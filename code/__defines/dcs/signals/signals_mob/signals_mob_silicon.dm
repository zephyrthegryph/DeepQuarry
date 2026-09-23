
//Non TG signals:
///from the base of /mob/living/silicon/robot/ClickOn(): (var/atom/A, var/params)
#define COMSIG_ROBOT_ITEM_ATTACK "robot_item_attack"
///called when a silicon is emp'd. from /mob/living/silicon/emp_act(severity)
#define COMSIG_SILICON_EMP_ACT "silicon_emp_act"
	#define COMPONENT_BLOCK_EMP (1<<0) //If this is set, the EMP will not go through. Used by other EMP acts as well.
///called when a robot is emp'd. from /mob/living/silicon/robot/emp_act(severity)
#define COMSIG_ROBOT_EMP_ACT "robot_emp_act"
