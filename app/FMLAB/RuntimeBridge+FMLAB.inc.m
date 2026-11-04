// FMLAB Linux: aggiunte FMLAB a LRRuntimeBridge (RuntimeBridge.m), tenute fuori dal file originale.
// Si include dentro @implementation LRRuntimeBridge: usa le stesse funzioni (LRSharedDirectory, lrError…).

// FMLAB: eliminazione sicura relativa a una cartella aperta: niente percorsi assoluti, i collegamenti simbolici
// vengono tolti come collegamenti (mai seguiti), profondità limitata.
static int FMLABRemoveAt(int base,const char *name,int depth){
    struct stat st;if(fstatat(base,name,&st,AT_SYMLINK_NOFOLLOW)<0)return errno;
    if(!S_ISDIR(st.st_mode))return unlinkat(base,name,0)<0?errno:0;
    if(depth>64)return ELOOP;
    int fd=openat(base,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);if(fd<0)return errno;
    DIR *d=fdopendir(fd);if(!d){int e=errno;close(fd);return e;}
    struct dirent *entry;int failure=0;
    while((entry=readdir(d))){if(!strcmp(entry->d_name,".")||!strcmp(entry->d_name,".."))continue;
        int e=FMLABRemoveAt(dirfd(d),entry->d_name,depth+1);if(e){failure=e;break;}}
    closedir(d);if(failure)return failure;
    return unlinkat(base,name,AT_REMOVEDIR)<0?errno:0;
}
+ (BOOL)deleteSharedItem:(NSString *)leaf relative:(NSString *)relative root:(NSString *)root error:(NSError **)error {
    if(!LRTransferString(leaf)||!lr_valid_leaf(leaf.UTF8String)){if(error)*error=lrError(EINVAL,@"Invalid filename.");return NO;}
    int fd=LRSharedDirectory(root,relative);if(fd<0){if(error)*error=lrError(errno,@"Cannot open the shared folder. Symbolic links are not followed.");return NO;}
    int result=FMLABRemoveAt(fd,leaf.UTF8String,0);close(fd);
    if(result&&error)*error=lrError(result,@"The item could not be deleted.");return result==0;
}
