#import "AniimoDraco.h"
#import <GLTFKit2/GLTFKit2.h>

#include "draco/compression/decode.h"

@interface AniimoDracoDecompressor : NSObject <GLTFDracoMeshDecompressor>
@end

static GLTFComponentType componentType(draco::DataType type) {
    switch (type) {
        case draco::DT_INT8: return GLTFComponentTypeByte;
        case draco::DT_UINT8: return GLTFComponentTypeUnsignedByte;
        case draco::DT_INT16: return GLTFComponentTypeShort;
        case draco::DT_UINT16: return GLTFComponentTypeUnsignedShort;
        case draco::DT_UINT32: return GLTFComponentTypeUnsignedInt;
        case draco::DT_FLOAT32: return GLTFComponentTypeFloat;
        default: return GLTFComponentTypeInvalid;
    }
}

static void *copyAttribute(const draco::PointCloud &cloud, const draco::PointAttribute &attribute, int &size) {
    const int pointCount = cloud.num_points();
    const int elementSize = attribute.num_components() * draco::DataTypeLength(attribute.data_type());
    size = pointCount * elementSize;
    void *data = malloc(size);
    if (attribute.is_mapping_identity()) {
        memcpy(data, attribute.GetAddress(draco::AttributeValueIndex(0)), size);
    } else {
        for (draco::PointIndex index(0); index < pointCount; ++index) {
            attribute.GetValue(attribute.mapped_index(index), static_cast<char *>(data) + index.value() * elementSize);
        }
    }
    return data;
}

@implementation AniimoDracoDecompressor

+ (GLTFPrimitive *)newPrimitiveForCompressedBufferView:(GLTFBufferView *)bufferView
                                          attributeMap:(NSDictionary<NSString *, NSNumber *> *)attributeMap {
    const char *bytes = static_cast<const char *>(bufferView.buffer.data.bytes) + bufferView.offset;
    draco::DecoderBuffer decoderBuffer;
    decoderBuffer.Init(bytes, bufferView.length);
    draco::Decoder decoder;
    auto type = draco::Decoder::GetEncodedGeometryType(&decoderBuffer);
    if (!type.ok() || type.value() != draco::TRIANGULAR_MESH) { return nil; }
    auto decoded = decoder.DecodeMeshFromBuffer(&decoderBuffer);
    if (!decoded.ok()) { return nil; }
    std::unique_ptr<draco::Mesh> mesh = std::move(decoded).value();
    draco::Mesh *meshPointer = mesh.get();

    NSMutableArray<GLTFAttribute *> *attributes = [NSMutableArray array];
    [attributeMap enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *identifier, BOOL *stop) {
        const draco::PointAttribute *attribute = meshPointer->GetAttributeByUniqueId(identifier.unsignedIntValue);
        if (attribute == nullptr) { return; }
        int length = 0;
        void *pointer = copyAttribute(*meshPointer, *attribute, length);
        NSData *data = [NSData dataWithBytesNoCopy:pointer length:length freeWhenDone:YES];
        GLTFBuffer *buffer = [[GLTFBuffer alloc] initWithData:data];
        GLTFBufferView *view = [[GLTFBufferView alloc] initWithBuffer:buffer length:length offset:0 stride:0];
        GLTFAccessor *accessor = [[GLTFAccessor alloc] initWithBufferView:view
                                                                 offset:0
                                                          componentType:componentType(attribute->data_type())
                                                              dimension:static_cast<GLTFValueDimension>(attribute->num_components())
                                                                  count:meshPointer->num_points()
                                                             normalized:attribute->normalized()];
        [attributes addObject:[[GLTFAttribute alloc] initWithName:key accessor:accessor]];
    }];

    const size_t indexCount = mesh->num_faces() * 3;
    const size_t byteCount = indexCount * sizeof(uint32_t);
    uint32_t *indices = static_cast<uint32_t *>(calloc(indexCount, sizeof(uint32_t)));
    for (int faceIndex = 0; faceIndex < mesh->num_faces(); ++faceIndex) {
        const auto &face = mesh->face(draco::FaceIndex(faceIndex));
        indices[faceIndex * 3] = face[0].value();
        indices[faceIndex * 3 + 1] = face[1].value();
        indices[faceIndex * 3 + 2] = face[2].value();
    }
    NSData *indexData = [NSData dataWithBytesNoCopy:indices length:byteCount freeWhenDone:YES];
    GLTFBuffer *indexBuffer = [[GLTFBuffer alloc] initWithData:indexData];
    GLTFBufferView *indexView = [[GLTFBufferView alloc] initWithBuffer:indexBuffer length:byteCount offset:0 stride:0];
    GLTFAccessor *indexAccessor = [[GLTFAccessor alloc] initWithBufferView:indexView
                                                                  offset:0
                                                           componentType:GLTFComponentTypeUnsignedInt
                                                               dimension:GLTFValueDimensionScalar
                                                                   count:indexCount
                                                              normalized:NO];
    return [[GLTFPrimitive alloc] initWithPrimitiveType:GLTFPrimitiveTypeTriangles attributes:attributes indices:indexAccessor];
}

@end

void AniimoRegisterDracoPlugin(void) {
    GLTFAsset.dracoDecompressorClassName = NSStringFromClass(AniimoDracoDecompressor.class);
}
