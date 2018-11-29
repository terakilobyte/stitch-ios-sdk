import MongoSwift

/*
 The update description for changed fields in a
 $changeStream operation.
*/
public class UpdateDescription: Codable {
    public let updatedFields: Document
    public let removedFields: [String]

    internal init(updatedFields: Document,
                  removedFields: [String]) {
        self.updatedFields = updatedFields
        self.removedFields = removedFields
    }

    /**
     * Lazily convert this update description to an update document.
     */
    public lazy var asUpdateDocument: Document = {
        var updateDocument = Document()

        if self.updatedFields.count > 0 {
            updateDocument["$set"] = self.updatedFields
        }

        if removedFields.count > 0 {
            var unset = Document()
            self.removedFields.forEach {
                unset[$0] = true
            }
            updateDocument["$unset"] = unset
        }

        return updateDocument
    }()
}

/**
 Find the diff between two documents.

 NOTE: This does not do a full diff on [BsonArray]. If there is
 an inequality between the old and new array, the old array will
 simply be replaced by the new one.

 - parameter ourDocument: original document
 - parameter theirDocument: document to diff on
 - parameter onKey: the key for our depth level
 - parameter updatedFields: contiguous document of updated fields,
 nested or otherwise
 - parameter removedFields: contiguous list of removedFields,
 nested or otherwise
 - returns: a description of the updated fields and removed keys between
 the documents
 */
private func diffBetween(ourDocument: Document,
                         theirDocument: Document,
                         onKey: String?,
                         updatedFields: inout Document,
                         removedFields: inout [String]) {
    // for each key in this document...
    ourDocument.forEach { (key, ourValue) in
        // don't worry about the _id or version field for now
        if key == "_id" || key == DOCUMENT_VERSION_FIELD {
            return
        }

        let actualKey = onKey == nil ? key : "\(onKey!).\(key)"

        // if the key exists in the other document AND both are BsonDocuments
        // diff the documents recursively, carrying over the keys to keep
        // updatedFields and removedFields flat.
        // this will allow us to reference whole objects as well as nested
        // properties.
        // else if the key does not exist, the key has been removed.
        if let theirValue = theirDocument[key] {
            if ourValue is Document && theirValue is Document {
                diffBetween(ourDocument: ourValue as! Document,
                            theirDocument: theirValue as! Document,
                            onKey: actualKey,
                            updatedFields: &updatedFields,
                            removedFields: &removedFields)
            } else if (!bsonEquals(ourValue, theirValue)) {
                updatedFields[actualKey] = theirValue
            }
        } else {
            if theirDocument.hasKey(key) {
                updatedFields[actualKey] = nil
            } else {
                removedFields.append(actualKey)
            }
        }
    }

    // for each key in the other document...
    theirDocument.forEach { (key, theirValue) in
        // don't worry about the _id or version field for now
        if key == "_id" || key == DOCUMENT_VERSION_FIELD {
            return
        }

        // if the key is not in the this document,
        // it is a new key with a new value.
        // updatedFields will included keys that must
        // be newly created.
        let actualKey = onKey == nil ? key : "\(onKey!).\(key)"
        guard let _ = ourDocument[key] else {
            updatedFields[actualKey] = theirValue
            return
        }
    }
}

extension Document {
    /**
     Find the diff between two documents.

     NOTE: This does not do a full diff on [BsonArray]. If there is
     an inequality between the old and new array, the old array will
     simply be replaced by the new one.

     -parameter otherDocument: document to diff on
     -returns: a description of the updated fields and removed keys between
     the documents
     */
    func diff(otherDocument: Document) -> UpdateDescription {
        var updatedFields = Document()
        var removedFields = [String]()
        diffBetween(ourDocument: self,
                    theirDocument: otherDocument,
                    onKey: nil,
                    updatedFields: &updatedFields,
                    removedFields: &removedFields)
        return UpdateDescription.init(updatedFields: updatedFields,
                                      removedFields: removedFields)
    }
}