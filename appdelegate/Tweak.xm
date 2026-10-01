#import <execinfo.h>
#import <mach-o/dyld.h>
#include <substrate.h>
#include <string.h>



// since the tweak is injected to the applications, it should be hidden in case of unexpected behaviors
static char *(*dyld_get_image_name_old)(uint32_t index);
char *dyld_get_image_name_new(uint32_t index);

char *dyld_get_image_name_new(uint32_t index)
{
    char *imageName = dyld_get_image_name_old(index);
    const char *tweakSuffix = "/Library/MobileSubstrate/DynamicLibraries/appdelegate.dylib";
    size_t imageNameLength = imageName ? strlen(imageName) : 0;
    size_t tweakSuffixLength = strlen(tweakSuffix);
    if (imageNameLength >= tweakSuffixLength &&
        strcmp(imageName + imageNameLength - tweakSuffixLength, tweakSuffix) == 0)
	{
		return "/System/Library/PrivateFrameworks/CertUI.framework/CertUIA";
	}
    return imageName;
}

%ctor {
    MSHookFunction((void *)_dyld_get_image_name,(void *)dyld_get_image_name_new, (void **)&dyld_get_image_name_old);
}
